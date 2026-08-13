// Foundry Agents capability host - binds the project's BYO connections (Cosmos thread
// store, Storage files, AI Search vectors) to the hosted-agents runtime.
//
// This is a SEPARATE module on purpose: the main template deploys it AFTER the RBAC
// module so the project's managed identity already has its data-plane roles when the
// capability host is created. The Infrastructure doc calls out capability-host creation
// failing on unpropagated RBAC as a top runtime-failure mode; this ordering avoids it.
//
// NOTE: capabilityHosts uses a PREVIEW API shape - validate at build time.

param foundryAccountName string
param projectName string
param cosmosConnectionName string
param storageConnectionName string
param searchConnectionName string

resource foundry 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: foundryAccountName
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' existing = {
  parent: foundry
  name: projectName
}

resource capabilityHost 'Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-04-01-preview' = {
  parent: project
  name: 'agents-capability-host'
  properties: {
    capabilityHostKind: 'Agents'
    threadStorageConnections: [
      cosmosConnectionName
    ]
    storageConnections: [
      storageConnectionName
    ]
    vectorStoreConnections: [
      searchConnectionName
    ]
  }
}

output id string = capabilityHost.id
output name string = capabilityHost.name
