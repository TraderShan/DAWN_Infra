// Cosmos DB (NoSQL, serverless, keyless) - the operational serve path.
// Holds the read models the surfaces render, the precomputed brief + ranking artifacts,
// the signals (with basis/basisRef), the three write targets, and - conditionally -
// app-managed conversation state. Private endpoint + diagnostics. Data-plane RBAC is
// applied centrally in modules/rbac.bicep.

param location string
param tags object
param name string
param peSubnetId string
param cosmosDnsZoneId string
param logAnalyticsId string

@description('Name of the application database created inside the account.')
param databaseName string = 'dawn'

@description('Containers to create (name + partitionKey). Matches the Data Architecture doc.')
param containers array = [
  { name: 'accounts', partitionKey: '/accountId' }
  { name: 'opportunities', partitionKey: '/accountId' }
  { name: 'calls', partitionKey: '/accountId' }
  { name: 'signals', partitionKey: '/accountId' }
  { name: 'artifacts', partitionKey: '/forDate' }      // brief + ranking artifacts (dated, versioned)
  { name: 'conversations', partitionKey: '/sessionId' } // app-managed memory (if not Foundry-managed)
]

resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' = {
  name: name
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    disableLocalAuth: true
    publicNetworkAccess: 'Disabled'
    enableAutomaticFailover: false
    capabilities: [
      {
        name: 'EnableServerless'
      }
    ]
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
  }
}

resource database 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-11-15' = {
  parent: cosmos
  name: databaseName
  properties: {
    resource: {
      id: databaseName
    }
  }
}

resource containerResources 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-11-15' = [for c in containers: {
  parent: database
  name: c.name
  properties: {
    resource: {
      id: c.name
      partitionKey: {
        paths: [
          c.partitionKey
        ]
        kind: 'Hash'
      }
    }
  }
}]

resource pe 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: 'pe-${name}'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: peSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'cosmos'
        properties: {
          privateLinkServiceId: cosmos.id
          groupIds: [
            'Sql'
          ]
        }
      }
    ]
  }
}

resource peDns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: pe
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'cosmos'
        properties: {
          privateDnsZoneId: cosmosDnsZoneId
        }
      }
    ]
  }
}

resource diag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-to-law'
  scope: cosmos
  properties: {
    workspaceId: logAnalyticsId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'Requests'
        enabled: true
      }
    ]
  }
}

output id string = cosmos.id
output name string = cosmos.name
output documentEndpoint string = cosmos.properties.documentEndpoint
output databaseName string = database.name
