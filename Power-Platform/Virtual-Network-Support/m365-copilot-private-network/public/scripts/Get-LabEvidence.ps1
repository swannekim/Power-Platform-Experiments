#requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][guid] $SubscriptionId,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $ResourceGroupName,
    [Parameter(Mandatory)][ValidateLength(1, 100)][string] $Nonce,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $OutputPath,
    [string] $DeploymentName = 'm365-copilot-private-network',
    [string] $TelemetryDeploymentName = 'm365-copilot-private-network-telemetry',
    [ValidateRange(1, 24)][int] $LookbackHours = 2,
    [ValidateRange(0, 600)][int] $WaitSeconds = 0,
    [ValidateRange(5, 60)][int] $PollIntervalSeconds = 15
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$PSNativeCommandUseErrorActionPreference = $false

function Invoke-AzJson {
    param([Parameter(Mandatory)][string[]] $Arguments)
    $result = & az @Arguments --subscription $SubscriptionId --only-show-errors --output json
    if ($LASTEXITCODE -ne 0) { throw "Read-only Azure CLI command failed: $($Arguments[0..1] -join ' ')." }
    if ($result) { ($result -join "`n") | ConvertFrom-Json }
}

function ConvertTo-KustoBase64 {
    param([string] $Value)
    [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Value))
}

$fullPath = [IO.Path]::GetFullPath($OutputPath)
if (Test-Path -LiteralPath $fullPath) {
    throw 'OutputPath already exists. Choose a new evidence filename to preserve prior observations.'
}
$main = Invoke-AzJson @(
    'deployment', 'group', 'show', '--resource-group', $ResourceGroupName, '--name', $DeploymentName,
    '--query', '{state:properties.provisioningState,apimName:properties.outputs.apimName.value,apimId:properties.outputs.apimId.value,apiId:properties.outputs.apiId.value,backendName:properties.outputs.backendName.value,backendBaseUrl:properties.outputs.backendBaseUrl.value,backendSubnetId:properties.outputs.backendSubnetId.value,backendNsgName:properties.outputs.backendNsgName.value,backendAccessRuleName:properties.outputs.backendAccessRuleName.value,virtualHubId:properties.outputs.virtualHubId.value}'
)
$telemetry = Invoke-AzJson @(
    'deployment', 'group', 'show', '--resource-group', $ResourceGroupName, '--name', $TelemetryDeploymentName,
    '--query', '{state:properties.provisioningState,apiId:properties.outputs.apiId.value,applicationInsightsId:properties.outputs.applicationInsightsId.value,workspaceName:properties.outputs.workspaceName.value,workspaceCustomerId:properties.outputs.workspaceCustomerId.value,diagnosticId:properties.outputs.diagnosticId.value,loggerId:properties.outputs.loggerId.value}'
)
if ($main.state -ne 'Succeeded' -or $telemetry.state -ne 'Succeeded') {
    throw 'Wait for both main and telemetry deployments to succeed before collecting evidence.'
}
if (-not $telemetry.workspaceCustomerId -or $telemetry.apiId -ne $main.apiId) {
    throw 'Telemetry outputs are missing or instrument a different API.'
}
$apim = Invoke-AzJson @(
    'apim', 'show', '--resource-group', $ResourceGroupName, '--name', $main.apimName,
    '--query', '{id:id,provisioningState:provisioningState,sku:sku,virtualNetworkType:virtualNetworkType,virtualNetworkConfiguration:virtualNetworkConfiguration,gatewayUrl:gatewayUrl}'
)
$api = Invoke-AzJson @(
    'rest', '--method', 'get', '--url', "https://management.azure.com$($main.apiId)?api-version=2024-05-01",
    '--query', '{id:id,path:properties.path,serviceUrl:properties.serviceUrl,subscriptionRequired:properties.subscriptionRequired,protocols:properties.protocols}'
)
$backend = Invoke-AzJson @(
    'webapp', 'show', '--resource-group', $ResourceGroupName, '--name', $main.backendName,
    '--query', '{id:id,state:state,publicNetworkAccess:publicNetworkAccess,httpsOnly:httpsOnly,defaultHostName:defaultHostName}'
)
$subnet = Invoke-AzJson @(
    'network', 'vnet', 'subnet', 'show', '--ids', $main.backendSubnetId,
    '--query', '{id:id,addressPrefix:addressPrefix,privateEndpointNetworkPolicies:privateEndpointNetworkPolicies,networkSecurityGroup:networkSecurityGroup.id}'
)
$rule = Invoke-AzJson @(
    'network', 'nsg', 'rule', 'show', '--resource-group', $ResourceGroupName,
    '--nsg-name', $main.backendNsgName, '--name', $main.backendAccessRuleName,
    '--query', '{id:id,name:name,access:access,direction:direction,priority:priority,protocol:protocol,sourceAddressPrefix:sourceAddressPrefix,sourcePortRange:sourcePortRange,destinationAddressPrefix:destinationAddressPrefix,destinationPortRange:destinationPortRange}'
)
$hub = Invoke-AzJson @(
    'rest', '--method', 'get', '--url', "https://management.azure.com$($main.virtualHubId)?api-version=2024-05-01",
    '--query', '{id:id,provisioningState:properties.provisioningState,routingState:properties.routingState,virtualRouterAutoScaleConfiguration:properties.virtualRouterAutoScaleConfiguration}'
)
$workspace = Invoke-AzJson @(
    'monitor', 'log-analytics', 'workspace', 'show', '--resource-group', $ResourceGroupName,
    '--workspace-name', $telemetry.workspaceName,
    '--query', '{id:id,provisioningState:provisioningState,retentionInDays:retentionInDays,workspaceCapping:workspaceCapping}'
)
$diagnostic = Invoke-AzJson @(
    'rest', '--method', 'get', '--url', "https://management.azure.com$($telemetry.diagnosticId)?api-version=2024-05-01",
    '--query', '{id:id,loggerId:properties.loggerId,alwaysLog:properties.alwaysLog,sampling:properties.sampling,httpCorrelationProtocol:properties.httpCorrelationProtocol,logClientIp:properties.logClientIp,frontend:properties.frontend,backend:properties.backend}'
)
$controlPlaneReadAtUtc = [DateTime]::UtcNow.ToString('o')

# Base64 confines caller input to a literal-safe alphabet; never interpolate the raw nonce into KQL.
$nonceLiteral = ConvertTo-KustoBase64 $Nonce
$insightsLiteral = ConvertTo-KustoBase64 $telemetry.applicationInsightsId
$backendHostLiteral = ConvertTo-KustoBase64 ([uri] $main.backendBaseUrl).Host
$query = @"
let ExpectedNonce = base64_decode_tostring('$nonceLiteral');
let ExpectedResource = base64_decode_tostring('$insightsLiteral');
let ExpectedBackendHost = base64_decode_tostring('$backendHostLiteral');
let Events = materialize(
    union isfuzzy=true
        (datatable(EvidenceKind:string, TimeGenerated:datetime, _ResourceId:string, Url:string, Data:string,
            Target:string, OperationId:string, Id:string, ParentId:string, Name:string, Success:bool,
            ResultCode:string, DurationMs:real, Properties:dynamic)[]),
        (AppRequests | extend EvidenceKind = 'request'),
        (AppDependencies | extend EvidenceKind = 'dependency')
    | where TimeGenerated > ago(${LookbackHours}h)
    | where _ResourceId =~ ExpectedResource
    | extend RawUrl = replace_regex(iff(EvidenceKind == 'request', Url, Data), @'^[A-Z]+ - ', '')
    | extend ParsedUrl = parse_url(RawUrl)
    | extend ObservedNonce = url_decode(replace_string(extract(@'[?&]nonce=([^&#]*)', 1, RawUrl), '+', '%20'))
);
let MatchingOperations = Events
    | where ObservedNonce == ExpectedNonce and isnotempty(OperationId)
    | distinct OperationId;
Events
| where ObservedNonce == ExpectedNonce or (isempty(ObservedNonce) and OperationId in (MatchingOperations))
| extend ExpectedBackend = EvidenceKind == 'dependency'
    and (tostring(ParsedUrl.Host) =~ ExpectedBackendHost or Target =~ ExpectedBackendHost)
| where EvidenceKind == 'request' or ExpectedBackend
| extend CapturedBody = coalesce(tostring(Properties['Response-Body']),
    tostring(Properties['BackendResponse-Body']), tostring(Properties['responseBody']),
    tostring(Properties['backendResponseBody']), tostring(Properties['ResponseBody']),
    tostring(Properties['BackendResponseBody']))
| extend Body = parse_json(substring(CapturedBody, 0, 4096))
| extend IsSyntheticBody = tobool(Body.synthetic) == true
| extend BackendObservationPresent = ExpectedBackend and IsSyntheticBody
    and tostring(Body.nonce) == ExpectedNonce and isnotempty(tostring(Body.observationId))
| project TimeGenerated, EvidenceKind, OperationId, Id, ParentId, Name, Success, ResultCode, DurationMs,
    ErrorMessage = tostring(Properties['ErrorMessage']),
    ErrorReason = tostring(Properties['ErrorReason']),
    ExactNonceMatch = ObservedNonce == ExpectedNonce, ExpectedBackend,
    BackendTarget = iff(ExpectedBackend, ExpectedBackendHost, ''),
    Url = strcat(tostring(ParsedUrl.Scheme), '://', tostring(ParsedUrl.Host), '/', trim_start('/', tostring(ParsedUrl.Path)),
        iff(isnotempty(ObservedNonce), strcat('?nonce=', url_encode(ObservedNonce)), '')),
    Nonce = ObservedNonce, BodyCaptured = isnotempty(CapturedBody), BackendObservationPresent,
    SyntheticResponse = iff(IsSyntheticBody, tostring(Body), ''),
    BackendObservedAtUtc = iff(IsSyntheticBody, tostring(Body.observedAtUtc), ''),
    BackendObservationId = iff(IsSyntheticBody, tostring(Body.observationId), '')
| order by TimeGenerated asc
| take 200
"@
# az.cmd cannot carry a multiline argument intact on Windows.
$query = $query -replace '\r?\n', ' '

$deadline = [DateTime]::UtcNow.AddSeconds($WaitSeconds)
$queryAttempts = 0
$events = @()
do {
    $queryAttempts++
    $events = @(Invoke-AzJson @(
        'monitor', 'log-analytics', 'query', '--workspace', $telemetry.workspaceCustomerId,
        '--analytics-query', $query, '--timespan', "PT${LookbackHours}H"
    ))
    $requestCount = @($events | Where-Object EvidenceKind -eq 'request').Count
    $dependencyCount = @($events | Where-Object EvidenceKind -eq 'dependency').Count
    $backendObservationCount = @($events | Where-Object { "$($_.BackendObservationPresent)" -eq 'true' }).Count
    if (($requestCount -gt 0 -and $dependencyCount -gt 0) -or [DateTime]::UtcNow -ge $deadline) { break }
    $remaining = [Math]::Max(1, [int]($deadline - [DateTime]::UtcNow).TotalSeconds)
    Start-Sleep -Seconds ([Math]::Min($PollIntervalSeconds, $remaining))
} while ($true)

$record = [ordered]@{
    recordedAtUtc = [DateTime]::UtcNow.ToString('o')
    nonce = $Nonce
    subscriptionId = $SubscriptionId.ToString()
    resourceGroupName = $ResourceGroupName
    controlPlane = [ordered]@{
        readAtUtc = $controlPlaneReadAtUtc
        interpretation = 'This is a non-atomic current-state snapshot, not proof of network state at the time of historical telemetry.'
        mainDeployment = $main
        telemetryDeployment = $telemetry
        apim = $apim
        api = $api
        backend = $backend
        backendSubnet = $subnet
        backendAccessRule = $rule
        virtualHub = $hub
        workspace = $workspace
        diagnostic = $diagnostic
    }
    telemetry = [ordered]@{
        queriedAtUtc = [DateTime]::UtcNow.ToString('o')
        lookbackHours = $LookbackHours
        queryAttempts = $queryAttempts
        exactNonceQuery = $true
        requestCount = $requestCount
        backendDependencyCount = $dependencyCount
        backendObservationCount = $backendObservationCount
        resultLimit = 200
        resultLimitReached = $events.Count -eq 200
        events = $events
        interpretation = 'Dependency telemetry proves an APIM backend attempt, not necessarily success. A matching synthetic backend response supplies stronger runtime evidence. No rows, missing tables, late ingestion, RBAC propagation, caps, or missing body capture never prove that no request occurred.'
    }
}
$null = New-Item -ItemType Directory -Path (Split-Path $fullPath -Parent) -Force
$record | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $fullPath -Encoding utf8
Write-Host "Saved evidence: $fullPath"
if ($requestCount -eq 0 -or $dependencyCount -eq 0) {
    Write-Warning 'Correlated telemetry is incomplete. Wait for propagation/ingestion and retry with a new output filename; absence is not proof of no request.'
}
if ($events.Count -eq 200) { Write-Warning 'The evidence row limit was reached; use a unique nonce and a shorter window.' }
[pscustomobject]@{
    outputPath = $fullPath
    requestCount = $requestCount
    backendDependencyCount = $dependencyCount
    backendObservationCount = $backendObservationCount
}
