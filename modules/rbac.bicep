// Centralized, keyless RBAC. Grants the UAMI and the Foundry project's managed identity
// the data-plane roles they need. Scoped to each target resource (referenced as existing).

param storageName string
param searchName string
param cosmosName string
param foundryName string
param acrName string
param keyVaultName string

param uamiPrincipalId string
param foundryProjectPrincipalId string

@description('Optional user/group object ID to also grant data roles for hands-on testing.')
param testerPrincipalId string = ''

var roles = {
  storageBlobDataContributor: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
  searchIndexDataContributor: '8ebe5a00-799e-43f5-93ac-243d3dce84a7'
  searchServiceContributor: '7ca78c08-252a-4471-8644-bb5ff32d4ba0'
  cognitiveServicesOpenAIUser: '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
  cognitiveServicesUser: 'a97b65f3-24c7-4388-baec-2e87135dc908'
  keyVaultSecretsUser: '4633458b-17de-408a-b874-0445c86b69e6'
  acrPull: '7f951dda-4ed3-4680-a7ca-43fe172d538d'
  // Control-plane role: lets the capability host create/read the 'enterprise_memory'
  // database + containers the Agents runtime provisions inside the BYO Cosmos account.
  cosmosDbOperator: '230815da-be43-4aae-9cb4-875f7bd000aa'
}
var cosmosDataContributorRoleId = '00000000-0000-0000-0000-000000000002'

// ---- existing target resources (for role-assignment scope) ----
resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageName
}
resource search 'Microsoft.Search/searchServices@2024-06-01-preview' existing = {
  name: searchName
}
resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' existing = {
  name: cosmosName
}
resource foundry 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: foundryName
}
resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' existing = {
  name: acrName
}
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

// ---- Storage Blob Data Contributor: UAMI + Foundry project ----
resource raStorageUami 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, uamiPrincipalId, roles.storageBlobDataContributor)
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.storageBlobDataContributor)
    principalId: uamiPrincipalId
    principalType: 'ServicePrincipal'
  }
}
resource raStorageProject 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, foundryProjectPrincipalId, roles.storageBlobDataContributor)
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.storageBlobDataContributor)
    principalId: foundryProjectPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// ---- AI Search: data + service contributor for UAMI + Foundry project ----
resource raSearchDataUami 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(search.id, uamiPrincipalId, roles.searchIndexDataContributor)
  scope: search
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.searchIndexDataContributor)
    principalId: uamiPrincipalId
    principalType: 'ServicePrincipal'
  }
}
resource raSearchSvcProject 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(search.id, foundryProjectPrincipalId, roles.searchServiceContributor)
  scope: search
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.searchServiceContributor)
    principalId: foundryProjectPrincipalId
    principalType: 'ServicePrincipal'
  }
}
resource raSearchDataProject 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(search.id, foundryProjectPrincipalId, roles.searchIndexDataContributor)
  scope: search
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.searchIndexDataContributor)
    principalId: foundryProjectPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// ---- Foundry account: OpenAI User for the UAMI ----
resource raOpenAiUami 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(foundry.id, uamiPrincipalId, roles.cognitiveServicesOpenAIUser)
  scope: foundry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.cognitiveServicesOpenAIUser)
    principalId: uamiPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// ---- Key Vault Secrets User: UAMI ----
resource raVaultUami 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, uamiPrincipalId, roles.keyVaultSecretsUser)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.keyVaultSecretsUser)
    principalId: uamiPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// ---- AcrPull: UAMI ----
resource raAcrUami 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, uamiPrincipalId, roles.acrPull)
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.acrPull)
    principalId: uamiPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// ---- Cosmos DB data-plane (Built-in Data Contributor): Foundry project + UAMI ----
resource cosmosRaProject 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-11-15' = {
  parent: cosmos
  name: guid(cosmos.id, foundryProjectPrincipalId, cosmosDataContributorRoleId)
  properties: {
    roleDefinitionId: '${cosmos.id}/sqlRoleDefinitions/${cosmosDataContributorRoleId}'
    principalId: foundryProjectPrincipalId
    scope: cosmos.id
  }
}
resource cosmosRaUami 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-11-15' = {
  parent: cosmos
  name: guid(cosmos.id, uamiPrincipalId, cosmosDataContributorRoleId)
  properties: {
    roleDefinitionId: '${cosmos.id}/sqlRoleDefinitions/${cosmosDataContributorRoleId}'
    principalId: uamiPrincipalId
    scope: cosmos.id
  }
}

// ---- Cosmos DB CONTROL-plane (Cosmos DB Operator): Foundry project ----
// Required so the capability host can create the 'enterprise_memory' database and its
// containers. Without this the capability host fails with a missing
// 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/read' authorization.
resource cosmosOperatorProject 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(cosmos.id, foundryProjectPrincipalId, roles.cosmosDbOperator)
  scope: cosmos
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.cosmosDbOperator)
    principalId: foundryProjectPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// ---- Optional tester (you) ----
resource raStorageTester 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(testerPrincipalId)) {
  name: guid(storage.id, testerPrincipalId, roles.storageBlobDataContributor)
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.storageBlobDataContributor)
    principalId: testerPrincipalId
    principalType: 'User'
  }
}
resource raOpenAiTester 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(testerPrincipalId)) {
  name: guid(foundry.id, testerPrincipalId, roles.cognitiveServicesUser)
  scope: foundry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.cognitiveServicesUser)
    principalId: testerPrincipalId
    principalType: 'User'
  }
}
