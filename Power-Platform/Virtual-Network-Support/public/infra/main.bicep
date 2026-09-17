targetScope = 'resourceGroup'

@description('Resource name prefix: use lowercase letters, numbers, and hyphens; start with a letter.')
@minLength(2)
@maxLength(24)
param labPrefix string = 'ppvnet'

@description('Primary Azure region. Use a supported region pair for the Power Platform environment geography.')
param primaryLocation string = 'westus'

@description('Power Platform failover Azure region; this does not deploy a SQL replica.')
param failoverLocation string = 'eastus'

@description('Power Platform enterprise policy geography, not an Azure compute region.')
param policyLocation string = 'unitedstates'

@description('Microsoft Entra object ID of the SQL administrator user.')
@minLength(36)
@maxLength(36)
param entraAdminObjectId string

@description('Microsoft Entra administrator user principal name.')
@minLength(1)
param entraAdminLogin string

@description('Tenant containing the Microsoft Entra SQL administrator.')
param tenantId string = subscription().tenantId

var tags = {
  lab: 'powerplatform-vnet-injection'
  purpose: 'synthetic-demo'
}
var namePrefix = toLower(labPrefix)
var delegatedSubnetName = 'snet-powerplatform'
var privateEndpointSubnetName = 'snet-private-endpoints'
var sqlDatabaseName = 'InventoryDemo'
var primaryDelegatedSubnetId = '${primaryVnet.id}/subnets/${delegatedSubnetName}'
var failoverDelegatedSubnetId = '${failoverVnet.id}/subnets/${delegatedSubnetName}'
var sqlPrivateEndpointSubnetId = '${primaryVnet.id}/subnets/${privateEndpointSubnetName}'

// Azure-provided DNS and unrestricted platform egress are intentional: no custom DNS, NSGs, or UDRs.
resource primaryVnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: '${namePrefix}-vnet-primary'
  location: primaryLocation
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.80.0.0/16'
      ]
    }
    subnets: [
      {
        name: delegatedSubnetName
        properties: {
          addressPrefix: '10.80.1.0/24'
          delegations: [
            {
              name: 'powerplatform'
              properties: {
                serviceName: 'Microsoft.PowerPlatform/enterprisePolicies'
              }
            }
          ]
        }
      }
      {
        name: privateEndpointSubnetName
        properties: {
          addressPrefix: '10.80.2.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

resource failoverVnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: '${namePrefix}-vnet-failover'
  location: failoverLocation
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.81.0.0/16'
      ]
    }
    subnets: [
      {
        name: delegatedSubnetName
        properties: {
          addressPrefix: '10.81.1.0/24'
          delegations: [
            {
              name: 'powerplatform'
              properties: {
                serviceName: 'Microsoft.PowerPlatform/enterprisePolicies'
              }
            }
          ]
        }
      }
    ]
  }
}

resource primaryToFailoverPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: primaryVnet
  name: 'primary-to-failover'
  properties: {
    remoteVirtualNetwork: {
      id: failoverVnet.id
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

resource failoverToPrimaryPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: failoverVnet
  name: 'failover-to-primary'
  properties: {
    remoteVirtualNetwork: {
      id: primaryVnet.id
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
    allowGatewayTransit: false
    useRemoteGateways: false
  }
  // Serialize the reciprocal peering updates against the same two VNets.
  dependsOn: [
    primaryToFailoverPeering
  ]
}

resource sqlPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink${environment().suffixes.sqlServerHostname}'
  location: 'global'
  tags: tags
}

resource primaryDnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: sqlPrivateDnsZone
  name: '${namePrefix}-dns-primary'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: primaryVnet.id
    }
  }
}

resource failoverDnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: sqlPrivateDnsZone
  name: '${namePrefix}-dns-failover'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: failoverVnet.id
    }
  }
  dependsOn: [
    primaryDnsLink
  ]
}

resource sqlServer 'Microsoft.Sql/servers@2023-08-01' = {
  name: '${namePrefix}-sql-${uniqueString(resourceGroup().id)}'
  location: primaryLocation
  tags: tags
  properties: {
    version: '12.0'
    // Entra-only authentication must be present on the initial server request for Azure Policy compliance.
    administrators: {
      administratorType: 'ActiveDirectory'
      login: entraAdminLogin
      sid: entraAdminObjectId
      tenantId: tenantId
      principalType: 'User'
      azureADOnlyAuthentication: true
    }
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Disabled'
  }
}

resource sqlConnectionPolicy 'Microsoft.Sql/servers/connectionPolicies@2023-08-01' = {
  parent: sqlServer
  name: 'default'
  properties: {
    connectionType: 'Proxy'
  }
}

resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-08-01' = {
  parent: sqlServer
  name: sqlDatabaseName
  location: primaryLocation
  tags: tags
  sku: {
    name: 'Basic'
    tier: 'Basic'
    capacity: 5
  }
  properties: {
    maxSizeBytes: 2147483648
    requestedBackupStorageRedundancy: 'Local'
    zoneRedundant: false
    readScale: 'Disabled'
  }
}

resource sqlPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: '${namePrefix}-pe-sql'
  location: primaryLocation
  tags: tags
  properties: {
    subnet: {
      id: sqlPrivateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${namePrefix}-sql-connection'
        properties: {
          privateLinkServiceId: sqlServer.id
          groupIds: [
            'sqlServer'
          ]
        }
      }
    ]
  }
}

resource sqlPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: sqlPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'sql'
        properties: {
          privateDnsZoneId: sqlPrivateDnsZone.id
        }
      }
    ]
  }
}

// Creates the policy only. Environment association is a separate Power Platform administration step.
resource enterprisePolicy 'Microsoft.PowerPlatform/enterprisePolicies@2020-10-30-preview' = {
  name: '${namePrefix}-policy-network-injection'
  location: policyLocation
  tags: tags
  kind: 'NetworkInjection'
  properties: {
    networkInjection: {
      virtualNetworks: [
        {
          id: primaryVnet.id
          subnet: {
            name: delegatedSubnetName
          }
        }
        {
          id: failoverVnet.id
          subnet: {
            name: delegatedSubnetName
          }
        }
      ]
    }
  }
}

output resourceGroupId string = resourceGroup().id
output sqlServerId string = sqlServer.id
output sqlServerName string = sqlServer.name
output serverFqdn string = sqlServer.properties.fullyQualifiedDomainName
output databaseId string = sqlDatabase.id
output databaseName string = sqlDatabase.name
output privateEndpointId string = sqlPrivateEndpoint.id
output privateEndpointName string = sqlPrivateEndpoint.name
output privateEndpointSubnetId string = sqlPrivateEndpointSubnetId
output privateDnsZoneId string = sqlPrivateDnsZone.id
output privateDnsZoneName string = sqlPrivateDnsZone.name
output policyArmId string = enterprisePolicy.id
output policyName string = enterprisePolicy.name
output primaryVnetId string = primaryVnet.id
output primaryVnetName string = primaryVnet.name
output failoverVnetId string = failoverVnet.id
output failoverVnetName string = failoverVnet.name
output primaryPowerPlatformSubnetId string = primaryDelegatedSubnetId
output failoverPowerPlatformSubnetId string = failoverDelegatedSubnetId
output powerPlatformSubnetName string = delegatedSubnetName
