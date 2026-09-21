targetScope = 'resourceGroup'

@description('Lowercase resource prefix, starting with a letter. Use 3-16 letters, digits, or hyphens.')
@minLength(3)
@maxLength(16)
param labPrefix string = 'copilot-private'

@description('APIM publisher contact supplied at deployment time, not stored in this repository.')
@minLength(1)
param publisherEmail string

@description('APIM publisher display name supplied at deployment time.')
@minLength(1)
param publisherName string

@allowed([
  'koreacentral'
])
param location string = 'koreacentral'

var prefix = toLower(labPrefix)
var suffix = uniqueString(resourceGroup().id)
var tags = {
  lab: 'm365-copilot-private-network'
  data: 'synthetic-only'
}
var hubPrefix = '10.90.0.0/24'
var apimVnetPrefix = '10.90.1.0/24'
var apimSubnetPrefix = '10.90.1.0/27'
var backendVnetPrefix = '10.90.2.0/24'
var backendSubnetPrefix = '10.90.2.0/27'
var apimSubnetName = 'snet-apim'
var backendSubnetName = 'snet-private-endpoints'
var backendRuleName = 'Apim-To-Backend-Https'
var apiName = 'synthetic-gateway'
var subscriptionName = 'synthetic-agent'

resource apimNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: '${prefix}-nsg-apim'
  location: location
  tags: tags
  properties: {
    // Keep default platform egress: no forced tunnel, outbound deny, or custom route table.
    securityRules: [
      {
        name: 'Internet-Https'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'Internet'
          sourcePortRange: '*'
          destinationAddressPrefix: apimSubnetPrefix
          destinationPortRange: '443'
        }
      }
      {
        name: 'ApiManagement-ControlPlane'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'ApiManagement'
          sourcePortRange: '*'
          destinationAddressPrefix: apimSubnetPrefix
          destinationPortRange: '3443'
        }
      }
      {
        name: 'AzureLoadBalancer-Probe'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: apimSubnetPrefix
          destinationPortRange: '6390'
        }
      }
    ]
  }
}

resource backendNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: '${prefix}-nsg-backend'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: backendRuleName
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: apimSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: backendSubnetPrefix
          destinationPortRange: '443'
        }
      }
      {
        name: 'Deny-Other-Inbound'
        properties: {
          priority: 200
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

resource apimVnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: '${prefix}-vnet-apim'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        apimVnetPrefix
      ]
    }
    subnets: [
      {
        name: apimSubnetName
        properties: {
          addressPrefix: apimSubnetPrefix
          networkSecurityGroup: {
            id: apimNsg.id
          }
          delegations: []
        }
      }
    ]
  }
}

resource backendVnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: '${prefix}-vnet-backend'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        backendVnetPrefix
      ]
    }
    subnets: [
      {
        name: backendSubnetName
        properties: {
          addressPrefix: backendSubnetPrefix
          networkSecurityGroup: {
            id: backendNsg.id
          }
          privateEndpointNetworkPolicies: 'NetworkSecurityGroupEnabled'
          delegations: []
        }
      }
    ]
  }
}

resource wan 'Microsoft.Network/virtualWans@2024-05-01' = {
  name: '${prefix}-vwan'
  location: location
  tags: tags
  properties: {
    type: 'Standard'
    allowBranchToBranchTraffic: true
    disableVpnEncryption: false
  }
}

resource hub 'Microsoft.Network/virtualHubs@2024-05-01' = {
  name: '${prefix}-hub'
  location: location
  tags: tags
  properties: {
    addressPrefix: hubPrefix
    sku: 'Standard'
    virtualWan: {
      id: wan.id
    }
    virtualRouterAutoScaleConfiguration: {
      minCapacity: 2
    }
  }
}

resource apimConnection 'Microsoft.Network/virtualHubs/hubVirtualNetworkConnections@2024-05-01' = {
  parent: hub
  name: 'apim-spoke'
  properties: {
    remoteVirtualNetwork: {
      id: apimVnet.id
    }
    enableInternetSecurity: false
    routingConfiguration: {
      associatedRouteTable: {
        id: '${hub.id}/hubRouteTables/defaultRouteTable'
      }
      propagatedRouteTables: {
        labels: [
          'default'
        ]
        ids: [
          {
            id: '${hub.id}/hubRouteTables/defaultRouteTable'
          }
        ]
      }
    }
  }
}

resource backendConnection 'Microsoft.Network/virtualHubs/hubVirtualNetworkConnections@2024-05-01' = {
  parent: hub
  name: 'backend-spoke'
  properties: {
    remoteVirtualNetwork: {
      id: backendVnet.id
    }
    enableInternetSecurity: false
    routingConfiguration: {
      associatedRouteTable: {
        id: '${hub.id}/hubRouteTables/defaultRouteTable'
      }
      propagatedRouteTables: {
        labels: [
          'default'
        ]
        ids: [
          {
            id: '${hub.id}/hubRouteTables/defaultRouteTable'
          }
        ]
      }
    }
  }
  // Both child writes update the same hub; serialize them to avoid operation conflicts.
  dependsOn: [
    apimConnection
  ]
}

resource dnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.azurewebsites.net'
  location: 'global'
  tags: tags
}

resource apimDnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: dnsZone
  name: 'apim-spoke'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: apimVnet.id
    }
  }
}

resource backendDnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: dnsZone
  name: 'backend-spoke'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: backendVnet.id
    }
  }
  dependsOn: [
    apimDnsLink
  ]
}

resource plan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: '${prefix}-plan'
  location: location
  tags: tags
  kind: 'linux'
  sku: {
    name: 'B1'
    tier: 'Basic'
    capacity: 1
  }
  properties: {
    reserved: true
  }
}

resource backend 'Microsoft.Web/sites@2024-04-01' = {
  name: '${prefix}-api-${suffix}'
  location: location
  tags: tags
  kind: 'app,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    publicNetworkAccess: 'Disabled'
    siteConfig: {
      linuxFxVersion: 'NODE|22-lts'
      appCommandLine: 'node /home/site/wwwroot/server.js'
      alwaysOn: true
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      ftpsState: 'Disabled'
      http20Enabled: false
      remoteDebuggingEnabled: false
      ipSecurityRestrictionsDefaultAction: 'Deny'
      ipSecurityRestrictions: [
        {
          name: 'Deny-All-Public'
          ipAddress: 'Any'
          action: 'Deny'
          priority: 2147483647
        }
      ]
      scmIpSecurityRestrictionsUseMain: false
      scmIpSecurityRestrictionsDefaultAction: 'Deny'
      scmIpSecurityRestrictions: [
        {
          name: 'Deny-All-Public-SCM'
          ipAddress: 'Any'
          action: 'Deny'
          priority: 2147483647
        }
      ]
      appSettings: [
        {
          name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
          value: 'false'
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~22'
        }
      ]
    }
  }
}

resource scmBasicAuth 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-04-01' = {
  parent: backend
  name: 'scm'
  properties: {
    allow: false
  }
}

resource ftpBasicAuth 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-04-01' = {
  parent: backend
  name: 'ftp'
  properties: {
    allow: false
  }
}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: '${prefix}-pe-backend'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: '${backendVnet.id}/subnets/${backendSubnetName}'
    }
    privateLinkServiceConnections: [
      {
        name: 'backend-sites'
        properties: {
          privateLinkServiceId: backend.id
          groupIds: [
            'sites'
          ]
        }
      }
    ]
  }
}

resource privateEndpointDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'appservice'
        properties: {
          privateDnsZoneId: dnsZone.id
        }
      }
    ]
  }
}

resource apim 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: '${prefix}-apim-${suffix}'
  location: location
  tags: tags
  sku: {
    name: 'Developer'
    capacity: 1
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
    virtualNetworkType: 'External'
    virtualNetworkConfiguration: {
      subnetResourceId: '${apimVnet.id}/subnets/${apimSubnetName}'
    }
    publicNetworkAccess: 'Enabled'
  }
  dependsOn: [
    backendConnection
    backendDnsLink
    privateEndpointDns
  ]
}

resource api 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apim
  name: apiName
  properties: {
    displayName: 'Synthetic private gateway'
    description: 'Read-only fake mail and SAP-shaped records. No real M365 or SAP connection.'
    path: 'synthetic'
    protocols: [
      'https'
    ]
    serviceUrl: 'https://${backend.properties.defaultHostName}'
    subscriptionRequired: true
    subscriptionKeyParameterNames: {
      header: 'Ocp-Apim-Subscription-Key'
      query: 'subscription-key'
    }
    format: 'openapi+json'
    value: loadTextContent('backend.openapi.json')
  }
}

resource policy 'Microsoft.ApiManagement/service/apis/policies@2024-05-01' = {
  parent: api
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: loadTextContent('api-policy.xml')
  }
}

resource apiSubscription 'Microsoft.ApiManagement/service/subscriptions@2024-05-01' = {
  parent: apim
  name: subscriptionName
  properties: {
    displayName: 'Synthetic declarative agent (API scoped)'
    scope: api.id
    state: 'active'
    allowTracing: false
  }
}

output location string = location
output resourceGroupName string = resourceGroup().name
output apimName string = apim.name
output apimId string = apim.id
output apimPrincipalId string = apim.identity.principalId
output apimSku string = apim.sku.name
output gatewayBaseUrl string = '${apim.properties.gatewayUrl}/synthetic'
output apiId string = api.id
output apiSubscriptionName string = apiSubscription.name
output apiSubscriptionScope string = api.id
output backendName string = backend.name
output backendId string = backend.id
output backendPrincipalId string = backend.identity.principalId
output backendBaseUrl string = 'https://${backend.properties.defaultHostName}'
output backendPublicNetworkAccess string = backend.properties.publicNetworkAccess
output appServicePlanName string = plan.name
output backendNsgName string = backendNsg.name
output backendNsgId string = backendNsg.id
output backendAccessRuleName string = backendRuleName
output apimNsgName string = apimNsg.name
output apimVnetId string = apimVnet.id
output apimSubnetId string = '${apimVnet.id}/subnets/${apimSubnetName}'
output apimSubnetPrefix string = apimSubnetPrefix
output backendVnetId string = backendVnet.id
output backendSubnetId string = '${backendVnet.id}/subnets/${backendSubnetName}'
output backendSubnetPrefix string = backendSubnetPrefix
output privateEndpointId string = privateEndpoint.id
output privateEndpointNicId string = privateEndpoint.properties.networkInterfaces[0].id
output privateDnsZoneName string = dnsZone.name
output virtualWanId string = wan.id
output virtualHubId string = hub.id
output virtualHubPrefix string = hubPrefix
output virtualHubMinCapacity int = 2
output hubConnectionIds array = [
  apimConnection.id
  backendConnection.id
]
