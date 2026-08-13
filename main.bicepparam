using './main.bicep'

// ----------------------------------------------------------------------------
//  Dawn POC parameters. Fill in the TODOs before deploying.
// ----------------------------------------------------------------------------

param location = 'swedencentral'
param workloadName = 'dawn'
param environmentName = 'poc'

param tags = {
  workload: 'dawn'
  environment: 'poc'
  managedBy: 'bicep'
  owner: 'shannichols@microsoft.com'
}

// --- Networking (matches the Infrastructure Architecture doc) ---
param vnetAddressPrefix = '192.168.0.0/16'
param agentSubnetPrefix = '192.168.0.0/24'
param peSubnetPrefix = '192.168.1.0/24'
param acaSubnetPrefix = '192.168.2.0/24'
param bastionSubnetPrefix = '192.168.3.0/26'
param appSvcSubnetPrefix = '192.168.4.0/24'
param mgmtSubnetPrefix = '192.168.5.0/24'
// NAT gateway gives the jumpbox + container apps outbound internet (deliberate deviation
// from strict "no public egress"). Outbound-only SNAT — no inbound exposure.
param deployNatGateway = true
param deployBastion = true
param bastionSku = 'Standard' // Standard enables Entra ID auth + native client

// --- Jumpbox (Windows management VM reached via Bastion; OFF by default) ---
// When deployJumpbox = true you MUST supply jumpboxAdminPassword securely. Do NOT hardcode
// it here. Preferred: reference a Key Vault secret from a real .bicepparam, e.g.
//   param jumpboxAdminPassword = az.getSecret('<sub>','<rg>','<kvName>','jumpbox-admin-password')
// or pass it at deploy time. Leaving it blank is fine while deployJumpbox = false.
param deployJumpbox = true
param jumpboxAdminUsername = 'azureadmin'
// Password is read from an environment variable at deploy time — never committed to source.
// Set it in your shell before deploying:  export JUMPBOX_ADMIN_PASSWORD='<StrongP@ssw0rd!>'
param jumpboxAdminPassword = readEnvironmentVariable('JUMPBOX_ADMIN_PASSWORD', '')
param jumpboxVmSize = 'Standard_D2s_v5'
// Entra login: users RDP with their MCAPS-tenant identity (…@MngEnvMCAP776009.onmicrosoft.com),
// NOT the corp @microsoft.com account. Below is Shan's MCAPS object ID.
param jumpboxEnableEntraLogin = true
param jumpboxEntraLoginPrincipalId = '9e631dcf-e79d-46ff-85a8-f3c15137b4e2'

// REDEPLOY SAFETY: false for the first deploy (creates the agent connections + capability
// host). After that first successful deploy, set this to TRUE so later redeploys skip them
// (the capability host locks the connections, so re-writing them fails otherwise).
// TRUE here because this environment's agent stack is already deployed. (Set back to false
// only if you ever deploy this template to a brand-new environment.)
param agentStackDeployed = true

// --- Foundry model — POC starter set: chat + embedding, each 100K TPM (capacity = 100) ---
// chat:      gpt-5.4 (GA) — replaces the deprecating gpt-4o / 2024-11-20.
// embedding: text-embedding-3-large (GA) — for AI Search vectorization.
// capacity is in units of 1,000 TPM, so 100 = 100,000 TPM. Each model draws from its OWN
// 1M-TPM GlobalStandard pool (sub: BuildForge Team 6), so no quota request is needed.
// To change throughput later, edit the *Capacity value and redeploy (raising it costs
// nothing — TPM quota is a rate ceiling, not a charge).
param deployModel = false
param chatModelName = 'gpt-5.4'
param chatModelVersion = '2025-03-05'
param chatModelDeploymentName = 'chat'
param chatModelCapacity = 100
param modelSkuName = 'GlobalStandard'
param deployEmbeddingModel = false
param embeddingModelName = 'text-embedding-3-large'
param embeddingModelVersion = '1'
param embeddingDeploymentName = 'embedding'
param embeddingCapacity = 100

// --- AI Search ---
param searchSku = 'basic'

// --- Compute ---
// Hello-world placeholder image (serves on port 80). targetPort below matches it.
param placeholderImage = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

// UI + four stub source systems + Toolbox MCP gateway.
// Ports are set to 80 for the placeholder image. When you push real FastAPI images to ACR,
// add 'image' and set targetPort to the port your app listens on (e.g. 8000), like:
//   { name: 'ui', targetPort: 8000, ingressEnabled: true, image: '<acr>.azurecr.io/dawn-ui:latest' }
param containerApps = [
  { name: 'ui', targetPort: 80, ingressEnabled: true }
  { name: 'stub-crm', targetPort: 80, ingressEnabled: true }
  { name: 'stub-products', targetPort: 80, ingressEnabled: true }
  { name: 'stub-core', targetPort: 80, ingressEnabled: true }
  { name: 'stub-knowledge', targetPort: 80, ingressEnabled: true }
  { name: 'toolbox', targetPort: 80, ingressEnabled: true }
]

// Overnight batch (scheduled ~5am US Eastern; cron is UTC) + manual data jobs.
param containerJobs = [
  { name: 'overnight-batch', triggerType: 'Schedule', cron: '0 9 * * *' }
  { name: 'seed-stubs', triggerType: 'Manual', cron: '' }
  { name: 'load-onelake', triggerType: 'Manual', cron: '' }
  { name: 'index-search', triggerType: 'Manual', cron: '' }
]

// --- Optional Web App (Dawn serves the UI on ACA, so keep this off) ---
// Setting deployWebApp = true deploys exactly TWO resources (not one per stub):
//   1. App Service plan  'plan-dawn-poc'        (Linux, SKU = appServicePlanSku below)
//   2. Web App           'app-dawn-poc-<suffix>' (single Linux container, running the
//      placeholderImage until you point it at a real ACR image)
// The Web App is PRIVATE: main.bicep passes computePublicIngress = false, so
// publicNetworkAccess = Disabled. It is VNet-integrated on snet-appsvc, HTTPS-only,
// and pulls from ACR via the managed identity. It does NOT create web apps for the
// UI or the four stubs - those stay as ACA container apps. Leave false unless you
// specifically need an App Service host alongside ACA.
param deployWebApp = false
param appServicePlanSku = 'B1'

// --- Front Door (Premium) + WAF — public, WAF-protected entry to the ui app ---
// ON. Fully deployable now: no Entra prerequisite. deploy.sh registers Microsoft.Cdn and
// approves the Private Link connection on the ACA env after the deployment. The internal
// ILB path (jumpbox curl over the greenbay-* zone) keeps working unchanged.
param deployFrontDoor = true
param wafMode = 'Prevention'       // switch to 'Detection' while tuning, then back to 'Prevention'
param wafRateLimitThreshold = 100  // requests/min per client IP before the WAF blocks

// --- EasyAuth (Entra ID sign-in on the ui app) ---
// TWO-PHASE by design. EasyAuth's redirect URI is https://<front-door-host>/.auth/login/aad/callback,
// and the Front Door host (a hashed name) only exists AFTER the first deploy. So:
//   Phase 1 (this deploy): deployFrontDoor = true, enableEasyAuth = false.
//   Phase 2: create the Entra app registration with that redirect URI (see
//            FRONTDOOR-EASYAUTH.md), fill easyAuthClientId below, export the secret, flip
//            enableEasyAuth = true, and redeploy.
// Leave false until the app registration exists — a true with an empty client id fails.
param enableEasyAuth = false
param easyAuthClientId = '62d78904-5445-4b99-a8ad-524cf4d21c73' // TODO Phase 2: az ad app create → paste the appId (client id) here
param easyAuthTenantId = '306fa087-3986-451e-bc29-a024111f5f55' // empty = this subscription's tenant (MCAPS) — single-tenant sign-in
// Secret is read from an env var at deploy time — never committed. Set before the Phase 2 deploy:
//   export EASYAUTH_CLIENT_SECRET='<app-registration-client-secret>'
param easyAuthClientSecret = readEnvironmentVariable('EASYAUTH_CLIENT_SECRET', '')

// --- Fabric ---
param fabricSkuName = 'F32'
// Fabric capacity admin(s). Fabric uses the Power BI / Fabric admin model, NOT Azure RBAC:
// a USER admin must be given as a UPN (email), and it must be a NATIVE member of the
// subscription's tenant (guests / cross-tenant UPNs are rejected). A SERVICE PRINCIPAL
// admin, by contrast, is given as its object ID. Below is Shan's native MCAPS-tenant UPN.
param fabricAdminMembers = [
  'shannichols@MngEnvMCAP776009.onmicrosoft.com'
]

// --- Optional: your Entra object ID for hands-on data access (az ad signed-in-user show --query id -o tsv) ---
param testerPrincipalId = ''
