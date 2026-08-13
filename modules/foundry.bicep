// Azure AI Foundry - AIServices account + project + BYO connections + optional model.
// The capability host is deliberately NOT created here; it lives in
// foundry-capabilityhost.bicep and is deployed AFTER RBAC so role assignments have
// propagated first (the Infrastructure doc flags capability-host-before-RBAC as a
// common runtime failure). Account uses network injection into the agent subnet so
// hosted-agent + tool traffic stays on the VNet (BYO-agent-tools posture).
//
// NOTE: connections / networkInjections use PREVIEW API shapes - validate at build time.

param location string
param tags object
param name string
param projectName string

param peSubnetId string
param agentSubnetId string
param openaiDnsZoneId string
param cognitiveDnsZoneId string
param aiservicesDnsZoneId string
param logAnalyticsId string

param storageId string
param storageBlobEndpoint string
param cosmosId string
param cosmosEndpoint string
param searchId string
param searchEndpoint string

param deployModel bool
param chatModelName string
param chatModelVersion string
param chatModelDeploymentName string
param chatModelCapacity int
param modelSkuName string

@description('Optional embedding model deployment for AI Search vectorization.')
param deployEmbeddingModel bool = false
param embeddingModelName string = 'text-embedding-3-large'
param embeddingModelVersion string = '1'
param embeddingDeploymentName string = 'embedding'
param embeddingCapacity int = 30

resource foundry 'Microsoft.CognitiveServices/accounts@2025-06-01' = {
  name: name
  location: location
  tags: tags
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    customSubDomainName: name
    publicNetworkAccess: 'Disabled'
    disableLocalAuth: true
    allowProjectManagement: true
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
    networkInjections: [
      {
        scenario: 'agent'
        subnetArmId: agentSubnetId
        useMicrosoftManagedNetwork: false
      }
    ]
  }
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' = {
  parent: foundry
  name: projectName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: 'Dawn Agent Project'
    description: 'Foundry project for the Dawn overnight agents + Ask Dawn (MAF hosted agents).'
  }
}

resource chatModel 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = if (deployModel) {
  parent: foundry
  name: chatModelDeploymentName
  sku: {
    name: modelSkuName
    capacity: chatModelCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: chatModelName
      version: chatModelVersion
    }
  }
}

resource embeddingModel 'Microsoft.CognitiveServices/accounts/deployments@2025-06-01' = if (deployEmbeddingModel) {
  parent: foundry
  name: embeddingDeploymentName
  sku: {
    name: modelSkuName
    capacity: embeddingCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: embeddingModelName
      version: embeddingModelVersion
    }
  }
  dependsOn: [
    chatModel
  ]
}

@description('Create the agent BYO connections. Set FALSE on redeploys after the capability host exists — once the caphost owns them, re-writing connections fails.')
param createAgentConnections bool = true

var agentConnectionNames = {
  cosmos: 'cosmos-thread-store'
  storage: 'storage-file-store'
  search: 'aisearch-knowledge'
}

resource cosmosConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = if (createAgentConnections) {
  parent: project
  name: agentConnectionNames.cosmos
  properties: {
    category: 'CosmosDB'
    target: cosmosEndpoint
    authType: 'AAD'
    isSharedToAll: true
    metadata: {
      ApiType: 'Azure'
      ResourceId: cosmosId
      location: location
    }
  }
}

resource storageConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = if (createAgentConnections) {
  parent: project
  name: agentConnectionNames.storage
  properties: {
    category: 'AzureStorageAccount'
    target: storageBlobEndpoint
    authType: 'AAD'
    isSharedToAll: true
    metadata: {
      ApiType: 'Azure'
      ResourceId: storageId
      location: location
    }
  }
}

resource searchConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = if (createAgentConnections) {
  parent: project
  name: agentConnectionNames.search
  properties: {
    category: 'CognitiveSearch'
    target: searchEndpoint
    authType: 'AAD'
    isSharedToAll: true
    metadata: {
      ApiType: 'Azure'
      ResourceId: searchId
      location: location
    }
  }
}

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
        name: 'account'
        properties: {
          privateLinkServiceId: foundry.id
          groupIds: [
            'account'
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
        name: 'openai'
        properties: {
          privateDnsZoneId: openaiDnsZoneId
        }
      }
      {
        name: 'cognitive'
        properties: {
          privateDnsZoneId: cognitiveDnsZoneId
        }
      }
      {
        name: 'aiservices'
        properties: {
          privateDnsZoneId: aiservicesDnsZoneId
        }
      }
    ]
  }
}

resource diag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-to-law'
  scope: foundry
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
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

output id string = foundry.id
output name string = foundry.name
output endpoint string = foundry.properties.endpoint
output projectName string = project.name
output projectId string = project.id
output projectPrincipalId string = project.identity.principalId
// Literal names (not resource.name) so they resolve even when connections are skipped on redeploy.
output cosmosConnectionName string = agentConnectionNames.cosmos
output storageConnectionName string = agentConnectionNames.storage
output searchConnectionName string = agentConnectionNames.search
