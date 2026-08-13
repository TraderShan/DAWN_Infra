# =====================================================================================
#  Dawn - Terraform - ACTIVE variable values  (auto-loaded by `terraform apply`)
# -------------------------------------------------------------------------------------
#  Generated from terraform.tfvars.example, mirroring main.bicepparam. Differences from
#  the example are intentional and called out inline:
#    * agent_stack_deployed = true  -> this environment's agent stack is ALREADY deployed.
#  The jumpbox password is NOT stored here. Supply it before deploying:
#    export TF_VAR_jumpbox_admin_password='<StrongP@ssw0rd!>'
# =====================================================================================

location         = "swedencentral"
workload_name    = "dawn"
environment_name = "poc"

tags = {
  workload    = "dawn"
  environment = "poc"
  managedBy   = "terraform"
  owner       = "shannichols@microsoft.com"
}

# --- Networking (matches the Infrastructure Architecture doc) ---
vnet_address_prefix   = "192.168.0.0/16"
agent_subnet_prefix   = "192.168.0.0/24"
pe_subnet_prefix      = "192.168.1.0/24"
aca_subnet_prefix     = "192.168.2.0/24"
bastion_subnet_prefix = "192.168.3.0/26"
appsvc_subnet_prefix  = "192.168.4.0/24"
mgmt_subnet_prefix    = "192.168.5.0/24"
# NAT gateway: outbound internet for the jumpbox + container apps (outbound-only SNAT,
# no inbound exposure). Deliberate deviation from strict "no public egress".
deploy_nat_gateway    = true
deploy_bastion        = true
bastion_sku           = "Standard" # Standard enables Entra ID auth + native client

# --- Jumpbox (Windows management VM reached via Bastion) ---
# Password comes from TF_VAR_jumpbox_admin_password (env var) — never committed here.
deploy_jumpbox         = true
jumpbox_admin_username = "azureadmin"
jumpbox_vm_size        = "Standard_D2s_v5"
# Entra login: users RDP with their MCAPS-tenant identity, not the corp @microsoft.com one.
enable_entra_login       = true
entra_login_principal_id = "9e631dcf-e79d-46ff-85a8-f3c15137b4e2"

# REDEPLOY SAFETY: TRUE here because this environment's agent connections + capability
# host are already deployed (and locked once created), so redeploys must skip them.
# (Set to false only if you ever point this config at a brand-new environment.)
agent_stack_deployed = true

# --- Foundry model — POC starter set: chat + embedding, each 100K TPM (capacity = 100) ---
# chat:      gpt-5.4 (GA) — replaces the deprecating gpt-4o / 2024-11-20.
# embedding: text-embedding-3-large (GA) — for AI Search vectorization.
# capacity is in units of 1,000 TPM, so 100 = 100,000 TPM. Each model draws from its OWN
# 1M-TPM GlobalStandard pool, so no quota request is needed. Raising it later costs
# nothing (TPM quota is a rate ceiling, not a charge).
deploy_model                = false
chat_model_name             = "gpt-5.4"
chat_model_version          = "2025-03-05"
chat_model_deployment_name  = "chat"
chat_model_capacity         = 100
model_sku_name              = "GlobalStandard"
deploy_embedding_model      = false
embedding_model_name        = "text-embedding-3-large"
embedding_model_version     = "1"
embedding_deployment_name   = "embedding"
embedding_capacity          = 100

# --- AI Search ---
search_sku = "basic"

# --- Compute ---
# Hello-world placeholder image (serves on port 80). target_port below matches it.
placeholder_image = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"

# UI + four stub source systems + Toolbox MCP gateway. Ports are 80 for the placeholder.
# When you push real FastAPI images, add `image` and set target_port to your app's port (e.g. 8000):
#   { name = "ui", target_port = 8000, ingress_enabled = true, image = "<acr>.azurecr.io/dawn-ui:latest" }
container_apps = [
  { name = "ui", target_port = 80, ingress_enabled = true },
  { name = "stub-crm", target_port = 80, ingress_enabled = true },
  { name = "stub-products", target_port = 80, ingress_enabled = true },
  { name = "stub-core", target_port = 80, ingress_enabled = true },
  { name = "stub-knowledge", target_port = 80, ingress_enabled = true },
  { name = "toolbox", target_port = 80, ingress_enabled = true },
]

# Overnight batch (scheduled ~5am US Eastern; cron is UTC) + manual data jobs.
container_jobs = [
  { name = "overnight-batch", trigger_type = "Schedule", cron = "0 9 * * *" },
  { name = "seed-stubs", trigger_type = "Manual", cron = "" },
  { name = "load-onelake", trigger_type = "Manual", cron = "" },
  { name = "index-search", trigger_type = "Manual", cron = "" },
]

# --- Optional Web App (Dawn serves the UI on ACA, so keep this off) ---
deploy_web_app       = false
app_service_plan_sku = "B1"

# --- Fabric ---
fabric_sku_name      = "F32"
# Fabric admins: a USER is given as a native-tenant UPN (not an object ID); a SERVICE
# PRINCIPAL is given as its object ID. Guests / cross-tenant UPNs are rejected.
fabric_admin_members = ["shannichols@MngEnvMCAP776009.onmicrosoft.com"]

# --- Optional: your Entra object id for hands-on data access ---
tester_principal_id = ""

# --- Front Door (Premium) + WAF — public, WAF-protected entry to the ui app ---
# ON. Fully deployable now: no Entra prerequisite. deploy.sh registers Microsoft.Cdn and
# approves the Private Link connection on the ACA env after apply. The internal ILB path
# (jumpbox curl over the greenbay-* zone) keeps working unchanged.
deploy_front_door        = true
waf_mode                 = "Prevention" # switch to "Detection" while tuning, then back
waf_rate_limit_threshold = 100          # requests/min per client IP before the WAF blocks

# --- EasyAuth (Entra ID sign-in on the ui app) ---
# TWO-PHASE by design. EasyAuth's redirect URI is https://<front-door-host>/.auth/login/aad/callback,
# and the Front Door host only exists AFTER the first apply. So:
#   Phase 1 (this apply): deploy_front_door = true, enable_easy_auth = false.
#   Phase 2: create the Entra app registration with that redirect URI (see
#            FRONTDOOR-EASYAUTH.md), set easy_auth_client_id below, export
#            TF_VAR_easy_auth_client_secret, flip enable_easy_auth = true, re-apply.
# Leave false until the app registration exists — a true with an empty client id fails.
enable_easy_auth    = false
easy_auth_client_id = "" # TODO Phase 2: az ad app create -> paste the appId (client id) here
easy_auth_tenant_id = "" # empty = this subscription's tenant (MCAPS) — single-tenant sign-in
# Secret comes from TF_VAR_easy_auth_client_secret (env var) — never committed here:
#   export TF_VAR_easy_auth_client_secret='<app-registration-client-secret>'
