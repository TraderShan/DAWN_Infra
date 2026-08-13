// =====================================================================================
//  Dawn - Infrastructure (private, Foundry-centered)  -  Orchestrator
// -------------------------------------------------------------------------------------
//  Recreates the POC stack for the "Dawn" solution per the five architecture documents.
//  Single region, private-by-design, keyless. Address space 192.168.0.0/16.
//
//  Key differences vs the original generic scaffold (gap closure):
//    * VNet re-addressed to 192.168.0.0/16 (agent 192.168.0.0/24, PE 192.168.1.0/24).
//    * No public ingress: ACA environment is internal; access via Azure Bastion.
//    * Foundry tool traffic kept on the VNet (agent network injection + internal ACA).
//    * Multiple ACA workloads: FastAPI UI + CRM/Products/Core/Knowledge stubs + Toolbox.
//    * Scheduled overnight batch job (~5am) + manual data-load / index jobs.
//    * Capability host split into its own module, deployed AFTER RBAC (propagation fix).
//    * Cosmos provisioned with the Dawn read-model / artifact / conversation containers.
//    * Web App carried forward but OFF by default (Dawn hosts the UI on ACA).
//
//  See README.md, ARCHITECTURE.md, NETWORKING.md, GAP-CLOSURE.md, OPERATIONS.md.
// =====================================================================================

targetScope = 'resourceGroup'

// ------------------------------- Parameters ------------------------------------------

@description('Azure region. Must support Foundry hosted agents; same region as the VNet.')
param location string = 'swedencentral'

@minLength(3)
@maxLength(10)
param workloadName string = 'dawn'

@maxLength(6)
param environmentName string = 'poc'

param tags object = {
  workload: 'dawn'
  environment: 'poc'
  managedBy: 'bicep'
}

// --- Networking (defaults match the Infrastructure doc) ---
param vnetAddressPrefix string = '192.168.0.0/16'
param agentSubnetPrefix string = '192.168.0.0/24'
param peSubnetPrefix string = '192.168.1.0/24'
param acaSubnetPrefix string = '192.168.2.0/24'
param bastionSubnetPrefix string = '192.168.3.0/26'
param appSvcSubnetPrefix string = '192.168.4.0/24'
param mgmtSubnetPrefix string = '192.168.5.0/24'

@description('Deploy a NAT gateway for outbound internet on the jumpbox + container-app subnets. A deliberate deviation from strict "no public egress".')
param deployNatGateway bool = false

@description('Deploy Azure Bastion as the secure access path (no public ingress).')
param deployBastion bool = true

@description('Bastion SKU. Standard enables Entra ID authentication + native client; Basic is minimal.')
@allowed([
  'Basic'
  'Standard'
])
param bastionSku string = 'Standard'

// --- Jumpbox (management VM reached via Bastion; OFF by default) ---
@description('Deploy a Windows jumpbox VM in snet-mgmt for Bastion-based access.')
param deployJumpbox bool = false
param jumpboxAdminUsername string = 'azureadmin'
@description('Jumpbox local admin password. Only needed when deployJumpbox = true. Supply securely (e.g. Key Vault getSecret in the .bicepparam), never hardcode in source.')
@secure()
param jumpboxAdminPassword string = ''
param jumpboxVmSize string = 'Standard_D2s_v5'

@description('Add Entra ID login to the jumpbox (extension + VM Administrator Login role).')
param jumpboxEnableEntraLogin bool = true
@description('Entra object ID to grant VM admin login — your MCAPS-tenant identity (not the corp @microsoft.com one).')
param jumpboxEntraLoginPrincipalId string = ''

@description('REDEPLOY SAFETY: leave false for the first deploy. Set true on later redeploys — once the Foundry capability host owns the agent connections, re-creating them fails, so this skips the connections + capability host on subsequent runs.')
param agentStackDeployed bool = false

// --- Foundry model (specify later; off by default) ---
param deployModel bool = false
param chatModelName string = 'gpt-4o'
param chatModelVersion string = '2024-11-20'
param chatModelDeploymentName string = 'chat'
param chatModelCapacity int = 30
param modelSkuName string = 'GlobalStandard'
param deployEmbeddingModel bool = false
param embeddingModelName string = 'text-embedding-3-large'
param embeddingModelVersion string = '1'
param embeddingDeploymentName string = 'embedding'
param embeddingCapacity int = 30

// --- AI Search ---
@allowed([
  'basic'
  'standard'
])
param searchSku string = 'basic'

// --- Compute ---
// Documented ACA hello-world placeholder (serves on port 80). Swap for your real
// app/stub/agent images in ACR later.
@description('Placeholder image used until you push your real images to ACR (serves on port 80).')
param placeholderImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

// targetPort matches the PLACEHOLDER image (port 80). When you deploy your real FastAPI
// images, set each app's targetPort to the port your app listens on (e.g. 8000).
@description('Container apps to deploy. Each: name, targetPort, ingressEnabled, optional image.')
param containerApps array = [
  { name: 'ui', targetPort: 80, ingressEnabled: true }
  { name: 'stub-crm', targetPort: 80, ingressEnabled: true }
  { name: 'stub-products', targetPort: 80, ingressEnabled: true }
  { name: 'stub-core', targetPort: 80, ingressEnabled: true }
  { name: 'stub-knowledge', targetPort: 80, ingressEnabled: true }
  { name: 'toolbox', targetPort: 80, ingressEnabled: true }
]

@description('Container jobs. Overnight batch is scheduled; data jobs are manual.')
param containerJobs array = [
  { name: 'overnight-batch', triggerType: 'Schedule', cron: '0 9 * * *' }
  { name: 'seed-stubs', triggerType: 'Manual', cron: '' }
  { name: 'load-onelake', triggerType: 'Manual', cron: '' }
  { name: 'index-search', triggerType: 'Manual', cron: '' }
]

// --- Optional Web App (Dawn hosts UI on ACA; off by default) ---
param deployWebApp bool = false
param appServicePlanSku string = 'B1'

// --- Front Door + WAF (public, WAF-protected entry to the ui app; OFF by default) ---
@description('Deploy Azure Front Door (Premium) + WAF in front of the ui app via Private Link. The internal ILB path (jumpbox) is unaffected.')
param deployFrontDoor bool = true 

@description('WAF mode. Prevention actively blocks; Detection only logs (use while tuning rules).')
@allowed([
  'Prevention'
  'Detection'
])
param wafMode string = 'Prevention'

@description('Requests per minute, per client IP, before the WAF rate-limit rule blocks.')
param wafRateLimitThreshold int = 100

// --- EasyAuth (Entra ID sign-in on the ui app; OFF by default) ---
@description('Enable EasyAuth (Entra ID) on the ui container app. Enforced on BOTH the Front Door and internal ILB paths.')
param enableEasyAuth bool = false

@description('Entra app registration (client) ID. Required when enableEasyAuth = true.')
param easyAuthClientId string = ''

@description('Entra tenant for EasyAuth sign-in. Empty = this subscription\'s tenant (single-tenant).')
param easyAuthTenantId string = ''

@description('Entra app registration client secret. Supply via env var; never hardcode. Required when enableEasyAuth = true.')
@secure()
param easyAuthClientSecret string = ''

// --- Fabric ---
param fabricSkuName string = 'F32'
@description('Fabric capacity administrators (UPNs / object IDs). At least one required.')
param fabricAdminMembers array

// --- Optional tester principal ---
param testerPrincipalId string = ''

// ------------------------------- Naming ----------------------------------------------

var suffix = toLower(uniqueString(resourceGroup().id, workloadName, environmentName))
var namePrefix = '${workloadName}-${environmentName}'

// EasyAuth signs users in against this tenant. Default to the subscription's own tenant
// (the MCAPS tenant here) for single-tenant sign-in.
var easyAuthTenantIdResolved = empty(easyAuthTenantId) ? subscription().tenantId : easyAuthTenantId

var names = {
  uami: 'id-${namePrefix}'
  vnet: 'vnet-${namePrefix}'
  bastion: 'bas-${namePrefix}'
  jumpbox: 'vm-jump-${namePrefix}'
  logAnalytics: 'log-${namePrefix}'
  appInsights: 'appi-${namePrefix}'
  keyVault: take('kv${workloadName}${suffix}', 24)
  storage: take('st${workloadName}${suffix}', 24)
  cosmos: 'cosmos-${namePrefix}-${suffix}'
  search: 'srch-${namePrefix}-${suffix}'
  acr: take('acr${workloadName}${suffix}', 50)
  foundry: 'aif-${namePrefix}-${suffix}'
  foundryProject: 'proj-${namePrefix}'
  acaEnv: 'cae-${namePrefix}'
  appPlan: 'plan-${namePrefix}'
  webApp: 'app-${namePrefix}-${suffix}'
  fabric: take(toLower('fab${workloadName}${suffix}'), 63)
}

// ============================ Foundation ============================================

module identity 'modules/identity.bicep' = {
  name: 'identity'
  params: {
    name: names.uami
    location: location
    tags: tags
  }
}

module network 'modules/network.bicep' = {
  name: 'network'
  params: {
    location: location
    tags: tags
    vnetName: names.vnet
    vnetAddressPrefix: vnetAddressPrefix
    agentSubnetPrefix: agentSubnetPrefix
    peSubnetPrefix: peSubnetPrefix
    acaSubnetPrefix: acaSubnetPrefix
    bastionSubnetPrefix: bastionSubnetPrefix
    appSvcSubnetPrefix: appSvcSubnetPrefix
    mgmtSubnetPrefix: mgmtSubnetPrefix
    deployNatGateway: deployNatGateway
  }
}

module observability 'modules/observability.bicep' = {
  name: 'observability'
  params: {
    location: location
    tags: tags
    logAnalyticsName: names.logAnalytics
    appInsightsName: names.appInsights
  }
}

module bastion 'modules/bastion.bicep' = if (deployBastion) {
  name: 'bastion'
  params: {
    location: location
    tags: tags
    name: names.bastion
    sku: bastionSku
    bastionSubnetId: network.outputs.bastionSubnetId
    logAnalyticsId: observability.outputs.logAnalyticsId
  }
}

module jumpbox 'modules/jumpbox.bicep' = if (deployJumpbox) {
  name: 'jumpbox'
  params: {
    location: location
    tags: tags
    name: names.jumpbox
    subnetId: network.outputs.mgmtSubnetId
    bastionSubnetPrefix: bastionSubnetPrefix
    adminUsername: jumpboxAdminUsername
    adminPassword: jumpboxAdminPassword
    vmSize: jumpboxVmSize
    logAnalyticsId: observability.outputs.logAnalyticsId
    enableEntraLogin: jumpboxEnableEntraLogin
    entraLoginPrincipalId: jumpboxEntraLoginPrincipalId
  }
}

// ============================ Data services ========================================

module storage 'modules/storage.bicep' = {
  name: 'storage'
  params: {
    location: location
    tags: tags
    name: names.storage
    peSubnetId: network.outputs.peSubnetId
    blobDnsZoneId: network.outputs.dnsZoneIds.blob
    logAnalyticsId: observability.outputs.logAnalyticsId
  }
}

module cosmos 'modules/cosmos.bicep' = {
  name: 'cosmos'
  params: {
    location: location
    tags: tags
    name: names.cosmos
    peSubnetId: network.outputs.peSubnetId
    cosmosDnsZoneId: network.outputs.dnsZoneIds.cosmos
    logAnalyticsId: observability.outputs.logAnalyticsId
  }
}

module search 'modules/search.bicep' = {
  name: 'search'
  params: {
    location: location
    tags: tags
    name: names.search
    sku: searchSku
    peSubnetId: network.outputs.peSubnetId
    searchDnsZoneId: network.outputs.dnsZoneIds.search
    logAnalyticsId: observability.outputs.logAnalyticsId
  }
}

module registry 'modules/registry.bicep' = {
  name: 'registry'
  params: {
    location: location
    tags: tags
    name: names.acr
    peSubnetId: network.outputs.peSubnetId
    acrDnsZoneId: network.outputs.dnsZoneIds.acr
    logAnalyticsId: observability.outputs.logAnalyticsId
  }
}

module keyvault 'modules/keyvault.bicep' = {
  name: 'keyvault'
  params: {
    location: location
    tags: tags
    name: names.keyVault
    tenantId: subscription().tenantId
    peSubnetId: network.outputs.peSubnetId
    vaultDnsZoneId: network.outputs.dnsZoneIds.vault
    logAnalyticsId: observability.outputs.logAnalyticsId
  }
}

// ============================ Foundry (core) =======================================

module foundry 'modules/foundry.bicep' = {
  name: 'foundry'
  params: {
    location: location
    tags: tags
    name: names.foundry
    projectName: names.foundryProject
    peSubnetId: network.outputs.peSubnetId
    agentSubnetId: network.outputs.agentSubnetId
    openaiDnsZoneId: network.outputs.dnsZoneIds.openai
    cognitiveDnsZoneId: network.outputs.dnsZoneIds.cognitive
    aiservicesDnsZoneId: network.outputs.dnsZoneIds.aiservices
    logAnalyticsId: observability.outputs.logAnalyticsId
    storageId: storage.outputs.id
    storageBlobEndpoint: storage.outputs.blobEndpoint
    cosmosId: cosmos.outputs.id
    cosmosEndpoint: cosmos.outputs.documentEndpoint
    searchId: search.outputs.id
    searchEndpoint: search.outputs.endpoint
    deployModel: deployModel
    chatModelName: chatModelName
    chatModelVersion: chatModelVersion
    chatModelDeploymentName: chatModelDeploymentName
    chatModelCapacity: chatModelCapacity
    modelSkuName: modelSkuName
    deployEmbeddingModel: deployEmbeddingModel
    embeddingModelName: embeddingModelName
    embeddingModelVersion: embeddingModelVersion
    embeddingDeploymentName: embeddingDeploymentName
    embeddingCapacity: embeddingCapacity
    createAgentConnections: !agentStackDeployed
  }
}

// ============================ RBAC (keyless) - BEFORE capability host ===============

module rbac 'modules/rbac.bicep' = {
  name: 'rbac'
  params: {
    storageName: names.storage
    searchName: names.search
    cosmosName: names.cosmos
    foundryName: names.foundry
    acrName: names.acr
    keyVaultName: names.keyVault
    uamiPrincipalId: identity.outputs.principalId
    foundryProjectPrincipalId: foundry.outputs.projectPrincipalId
    testerPrincipalId: testerPrincipalId
  }
  dependsOn: [
    storage
    cosmos
    search
    registry
    keyvault
  ]
}

// ============================ Foundry capability host - AFTER RBAC =================

module foundryCapabilityHost 'modules/foundry-capabilityhost.bicep' = if (!agentStackDeployed) {
  name: 'foundry-capabilityhost'
  params: {
    foundryAccountName: names.foundry
    projectName: foundry.outputs.projectName
    cosmosConnectionName: foundry.outputs.cosmosConnectionName
    storageConnectionName: foundry.outputs.storageConnectionName
    searchConnectionName: foundry.outputs.searchConnectionName
  }
  dependsOn: [
    rbac
  ]
}

// ============================ Compute - ACA env, apps, jobs =========================

module acaEnv 'modules/containerapps-env.bicep' = {
  name: 'aca-env'
  params: {
    location: location
    tags: tags
    name: names.acaEnv
    acaSubnetId: network.outputs.acaSubnetId
    logAnalyticsId: observability.outputs.logAnalyticsId
    logAnalyticsName: observability.outputs.logAnalyticsName
  }
}

// Private DNS zone so the internal env's app FQDNs resolve from inside the VNet.
module acaDns 'modules/aca-private-dns.bicep' = {
  name: 'aca-private-dns'
  params: {
    zoneName: acaEnv.outputs.defaultDomain
    staticIp: acaEnv.outputs.staticIp
    vnetId: network.outputs.vnetId
    vnetName: names.vnet
    tags: tags
  }
}

module apps 'modules/containerapp.bicep' = [for app in containerApps: {
  name: 'app-${app.name}'
  params: {
    location: location
    tags: tags
    name: '${namePrefix}-${app.name}'
    environmentId: acaEnv.outputs.id
    uamiId: identity.outputs.id
    acrLoginServer: registry.outputs.loginServer
    image: (contains(app, 'image') && !empty(app.image)) ? app.image : placeholderImage
    appInsightsConnectionString: observability.outputs.appInsightsConnectionString
    targetPort: app.targetPort
    ingressEnabled: app.ingressEnabled
    // EasyAuth is applied only to the ui app (the internet-facing surface).
    enableEasyAuth: enableEasyAuth && app.name == 'ui'
    easyAuthClientId: easyAuthClientId
    easyAuthTenantId: easyAuthTenantIdResolved
    easyAuthClientSecret: easyAuthClientSecret
  }
  dependsOn: [
    rbac
  ]
}]

module jobs 'modules/containerjob.bicep' = [for job in containerJobs: {
  name: 'job-${job.name}'
  params: {
    location: location
    tags: tags
    name: '${namePrefix}-${job.name}'
    environmentId: acaEnv.outputs.id
    uamiId: identity.outputs.id
    acrLoginServer: registry.outputs.loginServer
    image: (contains(job, 'image') && !empty(job.image)) ? job.image : placeholderImage
    appInsightsConnectionString: observability.outputs.appInsightsConnectionString
    triggerType: job.triggerType
    cronExpression: (contains(job, 'cron') && !empty(job.cron)) ? job.cron : '0 9 * * *'
  }
  dependsOn: [
    rbac
  ]
}]

// ============================ Front Door + WAF (OFF by default) =====================
// Public, WAF-protected entry to the ui app via Private Link. Adds an ingress path; the
// internal ILB path (jumpbox via the greenbay-* private DNS zone) is unaffected.
module frontdoor 'modules/frontdoor.bicep' = if (deployFrontDoor) {
  name: 'frontdoor'
  params: {
    tags: tags
    namePrefix: namePrefix
    acaEnvironmentId: acaEnv.outputs.id
    privateLinkLocation: location
    // ui app FQDN on the internal env (external ingress = no ".internal." segment).
    originHostName: '${namePrefix}-ui.${acaEnv.outputs.defaultDomain}'
    wafMode: wafMode
    rateLimitThreshold: wafRateLimitThreshold
  }
  dependsOn: [
    apps
  ]
}

// ============================ Optional Web App (OFF by default) =====================

module webapp 'modules/webapp.bicep' = if (deployWebApp) {
  name: 'webapp'
  params: {
    location: location
    tags: tags
    planName: names.appPlan
    webAppName: names.webApp
    appServicePlanSku: appServicePlanSku
    appSvcSubnetId: network.outputs.appSvcSubnetId
    logAnalyticsId: observability.outputs.logAnalyticsId
    uamiId: identity.outputs.id
    uamiClientId: identity.outputs.clientId
    appInsightsConnectionString: observability.outputs.appInsightsConnectionString
    sampleContainerImage: placeholderImage
    computePublicIngress: false // keep private even if enabled
  }
  dependsOn: [
    rbac
  ]
}

// ============================ Fabric ===============================================

module fabric 'modules/fabric.bicep' = {
  name: 'fabric'
  params: {
    location: location
    tags: tags
    name: names.fabric
    skuName: fabricSkuName
    adminMembers: fabricAdminMembers
  }
}

// ============================ Outputs ==============================================

output managedIdentityClientId string = identity.outputs.clientId
output vnetId string = network.outputs.vnetId
output bastionName string = deployBastion ? bastion.outputs.name : ''
output jumpboxName string = deployJumpbox ? jumpbox.outputs.name : ''
output jumpboxPrivateIp string = deployJumpbox ? jumpbox.outputs.privateIp : ''
output appInsightsConnectionString string = observability.outputs.appInsightsConnectionString
output foundryAccountName string = foundry.outputs.name
output foundryEndpoint string = foundry.outputs.endpoint
output foundryProjectName string = foundry.outputs.projectName
output searchEndpoint string = search.outputs.endpoint
output cosmosEndpoint string = cosmos.outputs.documentEndpoint
output cosmosDatabaseName string = cosmos.outputs.databaseName
output storageAccountName string = storage.outputs.name
output keyVaultName string = keyvault.outputs.name
output acrLoginServer string = registry.outputs.loginServer
output acaEnvironmentName string = acaEnv.outputs.name
output fabricCapacityName string = fabric.outputs.name
@description('Public Front Door hostname for the ui app (empty when deployFrontDoor = false). Browse https://<this>.')
output frontDoorEndpointHostName string = deployFrontDoor ? frontdoor.outputs.endpointHostName : ''
