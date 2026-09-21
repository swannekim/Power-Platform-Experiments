targetScope = 'resourceGroup'

@description('Existing, fully provisioned lab APIM instance in this resource group. Deploy separately after main.bicep completes.')
@minLength(1)
param existingApimName string

@description('This module intentionally instruments only the synthetic lab API, never all APIs.')
@allowed([
  'synthetic-gateway'
])
param existingApiName string = 'synthetic-gateway'

@minLength(3)
@maxLength(16)
param labPrefix string = 'copilot-private'

@allowed([
  'koreacentral'
])
param location string = 'koreacentral'

@description('Workspace ingestion cap in GB/day; best effort, not a hard billing limit. Reaching it creates evidence gaps.')
@minValue(1)
@maxValue(5)
param dailyQuotaGb int = 1

var prefix = toLower(labPrefix)
var suffix = uniqueString(resourceGroup().id, existingApimName)
var tags = {
  lab: 'm365-copilot-private-network'
  data: 'synthetic-only'
}
var monitoringMetricsPublisherRoleId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '3913510d-42f4-4e42-8a64-420c390055eb'
)
var maskedHeaders = [
  { mode: 'Mask', value: 'Authorization' }
  { mode: 'Mask', value: 'Ocp-Apim-Subscription-Key' }
  { mode: 'Mask', value: 'Cookie' }
  { mode: 'Mask', value: 'Set-Cookie' }
  { mode: 'Mask', value: 'X-Forwarded-For' }
  { mode: 'Mask', value: 'X-Real-IP' }
]
var maskedQueries = [
  { mode: 'Hide', value: 'subscription-key' }
  { mode: 'Hide', value: 'access_token' }
  { mode: 'Hide', value: 'token' }
  { mode: 'Hide', value: 'api-key' }
  { mode: 'Hide', value: 'apikey' }
  { mode: 'Hide', value: 'code' }
]
var requestCapture = {
  headers: []
  body: {
    bytes: 0
  }
  dataMasking: {
    headers: maskedHeaders
    queryParams: maskedQueries
  }
}
var responseCapture = {
  headers: []
  body: {
    bytes: 4096
  }
  dataMasking: {
    headers: maskedHeaders
    queryParams: maskedQueries
  }
}

resource apim 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: existingApimName
}

resource api 'Microsoft.ApiManagement/service/apis@2024-05-01' existing = {
  parent: apim
  name: existingApiName
}

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${prefix}-logs-${suffix}'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    workspaceCapping: {
      dailyQuotaGb: dailyQuotaGb
    }
    features: {
      disableLocalAuth: true
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

resource insights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${prefix}-insights-${suffix}'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: workspace.id
    IngestionMode: 'LogAnalytics'
    RetentionInDays: 30
    SamplingPercentage: 100
    DisableIpMasking: false
    DisableLocalAuth: true
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Use the existing APIM identity, not an API key or a secret supplied by the operator.
resource telemetryPublisher 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(insights.id, apim.id, monitoringMetricsPublisherRoleId)
  scope: insights
  properties: {
    roleDefinitionId: monitoringMetricsPublisherRoleId
    principalId: apim.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

resource logger 'Microsoft.ApiManagement/service/loggers@2024-05-01' = {
  parent: apim
  name: 'synthetic-observations'
  properties: {
    loggerType: 'applicationInsights'
    description: 'Synthetic API evidence only; managed identity, no logged headers or client IP.'
    resourceId: insights.id
    credentials: {
      connectionString: insights.properties.ConnectionString
      identityClientId: 'SystemAssigned'
    }
    isBuffered: true
  }
  dependsOn: [
    telemetryPublisher
  ]
}

resource diagnostic 'Microsoft.ApiManagement/service/apis/diagnostics@2024-05-01' = {
  parent: api
  name: 'applicationinsights'
  properties: {
    loggerId: logger.id
    alwaysLog: 'allErrors'
    sampling: {
      samplingType: 'fixed'
      percentage: 100
    }
    httpCorrelationProtocol: 'W3C'
    logClientIp: false
    metrics: false
    operationNameFormat: 'Name'
    verbosity: 'information'
    frontend: {
      request: requestCapture
      response: responseCapture
    }
    backend: {
      request: requestCapture
      response: responseCapture
    }
  }
}

output applicationInsightsId string = insights.id
output applicationInsightsName string = insights.name
output workspaceId string = workspace.id
output workspaceName string = workspace.name
output workspaceCustomerId string = workspace.properties.customerId
output apiId string = api.id
output diagnosticId string = diagnostic.id
output loggerId string = logger.id
output telemetryPublisherRoleAssignmentId string = telemetryPublisher.id
output apimPrincipalId string = apim.identity.principalId
output workspaceRetentionInDays int = 30
output dailyQuotaGb int = dailyQuotaGb
output responseBodyLimitBytes int = 4096
output evidenceTables array = [
  'AppRequests'
  'AppDependencies'
]
output readinessNote string = 'Wait for main deployment and this deployment to succeed, then send a fresh nonce. RBAC, APIM configuration, and ingestion may take minutes. No matching logs does not prove no request. App table retention can override the workspace default.'
