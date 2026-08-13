# =====================================================================================
#  Dawn - Terraform - Input variables
# -------------------------------------------------------------------------------------
#  Mirrors the parameters of main.bicep (defaults match main.bicepparam / the docs).
# =====================================================================================

variable "location" {
  description = "Azure region. Must support Foundry hosted agents; same region as the VNet."
  type        = string
  default     = "swedencentral"
}

variable "workload_name" {
  description = "Short workload name (3-10 chars) used in resource naming."
  type        = string
  default     = "dawn"

  validation {
    condition     = length(var.workload_name) >= 3 && length(var.workload_name) <= 10
    error_message = "workload_name must be between 3 and 10 characters."
  }
}

variable "environment_name" {
  description = "Short environment name (<= 6 chars)."
  type        = string
  default     = "poc"

  validation {
    condition     = length(var.environment_name) <= 6
    error_message = "environment_name must be 6 characters or fewer."
  }
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default = {
    workload    = "dawn"
    environment = "poc"
    managedBy   = "bicep"
  }
}

# --- Networking (defaults match the Infrastructure Architecture doc) ---
variable "vnet_address_prefix" {
  description = "VNet address space."
  type        = string
  default     = "192.168.0.0/16"
}

variable "agent_subnet_prefix" {
  description = "snet-agent - delegated to Microsoft.App/environments (Foundry hosted agents)."
  type        = string
  default     = "192.168.0.0/24"
}

variable "pe_subnet_prefix" {
  description = "snet-pe - private endpoints (PE network policies disabled)."
  type        = string
  default     = "192.168.1.0/24"
}

variable "aca_subnet_prefix" {
  description = "snet-aca - delegated to Microsoft.App/environments (ACA workloads)."
  type        = string
  default     = "192.168.2.0/24"
}

variable "bastion_subnet_prefix" {
  description = "AzureBastionSubnet (fixed name, /26 minimum)."
  type        = string
  default     = "192.168.3.0/26"
}

variable "appsvc_subnet_prefix" {
  description = "snet-appsvc - delegated to Microsoft.Web/serverFarms (optional Web App)."
  type        = string
  default     = "192.168.4.0/24"
}

variable "mgmt_subnet_prefix" {
  description = "snet-mgmt - undelegated; hosts the optional jumpbox VM."
  type        = string
  default     = "192.168.5.0/24"
}

variable "deploy_nat_gateway" {
  description = "Deploy a NAT gateway for outbound internet on snet-mgmt (jumpbox) + snet-aca (container apps). A deliberate deviation from strict 'no public egress'."
  type        = bool
  default     = false
}

# --- Bastion ---
variable "deploy_bastion" {
  description = "Deploy Azure Bastion as the secure access path (no public ingress)."
  type        = bool
  default     = true
}

variable "bastion_sku" {
  description = "Bastion SKU. Standard enables Entra ID auth + native client; Basic is minimal."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Basic", "Standard"], var.bastion_sku)
    error_message = "bastion_sku must be Basic or Standard."
  }
}

# --- Jumpbox (Windows management VM reached via Bastion; OFF by default) ---
variable "deploy_jumpbox" {
  description = "Deploy a Windows jumpbox VM in snet-mgmt for Bastion-based access."
  type        = bool
  default     = false
}

variable "jumpbox_admin_username" {
  description = "Jumpbox local administrator username."
  type        = string
  default     = "azureadmin"
}

variable "jumpbox_admin_password" {
  description = "Jumpbox local admin password. Required only when deploy_jumpbox = true. Supply via TF_VAR_jumpbox_admin_password or a Key Vault data source; never commit it."
  type        = string
  default     = ""
  sensitive   = true
}

variable "jumpbox_vm_size" {
  description = "Jumpbox VM size."
  type        = string
  default     = "Standard_D2s_v5"
}

variable "enable_entra_login" {
  description = "Add the AADLoginForWindows extension so users sign in with their Entra (MCAPS-tenant) identity."
  type        = bool
  default     = true
}

variable "entra_login_principal_id" {
  description = "Entra object ID granted 'Virtual Machine Administrator Login' on the jumpbox (your MCAPS-tenant identity). Empty = skip the role assignment."
  type        = string
  default     = ""
}

# --- Foundry model (specify later; off by default) ---
variable "deploy_model" {
  description = "Deploy the chat model deployment on the Foundry account."
  type        = bool
  default     = false
}

variable "agent_stack_deployed" {
  description = "REDEPLOY SAFETY: false for the first deploy (creates the agent connections + capability host). Set true on later redeploys so they're skipped — the capability host locks the connections, so re-writing them fails otherwise."
  type        = bool
  default     = false
}

variable "chat_model_name" {
  description = "Chat model name."
  type        = string
  default     = "gpt-4o"
}

variable "chat_model_version" {
  description = "Chat model version."
  type        = string
  default     = "2024-11-20"
}

variable "chat_model_deployment_name" {
  description = "Chat model deployment name."
  type        = string
  default     = "chat"
}

variable "chat_model_capacity" {
  description = "Chat model capacity (TPM units)."
  type        = number
  default     = 30
}

variable "model_sku_name" {
  description = "Model deployment SKU name."
  type        = string
  default     = "GlobalStandard"
}

variable "deploy_embedding_model" {
  description = "Optional embedding model deployment for AI Search vectorization."
  type        = bool
  default     = false
}

variable "embedding_model_name" {
  description = "Embedding model name."
  type        = string
  default     = "text-embedding-3-large"
}

variable "embedding_model_version" {
  description = "Embedding model version."
  type        = string
  default     = "1"
}

variable "embedding_deployment_name" {
  description = "Embedding model deployment name."
  type        = string
  default     = "embedding"
}

variable "embedding_capacity" {
  description = "Embedding model capacity (TPM units)."
  type        = number
  default     = 30
}

# --- AI Search ---
variable "search_sku" {
  description = "Azure AI Search SKU."
  type        = string
  default     = "basic"

  validation {
    condition     = contains(["basic", "standard"], var.search_sku)
    error_message = "search_sku must be basic or standard."
  }
}

# --- Compute ---
variable "placeholder_image" {
  description = "Hello-world placeholder image (serves on port 80) used until real images are pushed to ACR."
  type        = string
  default     = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
}

variable "container_apps" {
  # target_port is 80 to match the placeholder image. When you push real FastAPI images,
  # set target_port to the port your app listens on (e.g. 8000).
  description = "Container apps to deploy. Each: name, target_port, ingress_enabled, optional image."
  type = list(object({
    name            = string
    target_port     = number
    ingress_enabled = bool
    image           = optional(string)
  }))
  default = [
    { name = "ui", target_port = 80, ingress_enabled = true },
    { name = "stub-crm", target_port = 80, ingress_enabled = true },
    { name = "stub-products", target_port = 80, ingress_enabled = true },
    { name = "stub-core", target_port = 80, ingress_enabled = true },
    { name = "stub-knowledge", target_port = 80, ingress_enabled = true },
    { name = "toolbox", target_port = 80, ingress_enabled = true },
  ]
}

variable "container_jobs" {
  description = "Container jobs. Overnight batch is scheduled; data jobs are manual."
  type = list(object({
    name         = string
    trigger_type = string
    cron         = optional(string, "")
    image        = optional(string)
  }))
  default = [
    { name = "overnight-batch", trigger_type = "Schedule", cron = "0 9 * * *" },
    { name = "seed-stubs", trigger_type = "Manual", cron = "" },
    { name = "load-onelake", trigger_type = "Manual", cron = "" },
    { name = "index-search", trigger_type = "Manual", cron = "" },
  ]
}

# --- Optional Web App (Dawn hosts UI on ACA; off by default) ---
# Setting deploy_web_app = true deploys exactly TWO resources (not one per stub):
#   1. azurerm_service_plan.web   'plan-dawn-poc'         (Linux, SKU = app_service_plan_sku)
#   2. azurerm_linux_web_app.web  'app-dawn-poc-<suffix>' (single Linux container, running
#      placeholder_image until you point it at a real ACR image)
# The Web App is PRIVATE: public_network_access_enabled = false. It is VNet-integrated on
# snet-appsvc, HTTPS-only, and pulls from ACR via the managed identity. It does NOT create
# web apps for the UI or the four stubs - those stay as ACA container apps. Leave false
# unless you specifically need an App Service host alongside ACA.
variable "deploy_web_app" {
  description = "Deploy the optional App Service Web App (kept private even when enabled)."
  type        = bool
  default     = false
}

variable "app_service_plan_sku" {
  description = "App Service plan SKU (Linux)."
  type        = string
  default     = "B1"
}

# --- Fabric ---
variable "fabric_sku_name" {
  description = "Microsoft Fabric capacity SKU name."
  type        = string
  default     = "F4"
}

variable "fabric_admin_members" {
  description = "Fabric capacity administrators (UPNs / object IDs). At least one required."
  type        = list(string)
}

# --- Optional tester principal ---
variable "tester_principal_id" {
  description = "Optional user/group object id also granted data roles for hands-on testing."
  type        = string
  default     = ""
}

# --- Front Door + WAF (public, WAF-protected entry to the ui app; OFF by default) ---
variable "deploy_front_door" {
  description = "Deploy Azure Front Door (Premium) + WAF in front of the ui app via Private Link. The internal ILB path (jumpbox) is unaffected."
  type        = bool
  default     = false
}

variable "waf_mode" {
  description = "WAF mode. Prevention actively blocks; Detection only logs (use while tuning rules)."
  type        = string
  default     = "Prevention"

  validation {
    condition     = contains(["Prevention", "Detection"], var.waf_mode)
    error_message = "waf_mode must be Prevention or Detection."
  }
}

variable "waf_rate_limit_threshold" {
  description = "Requests per minute, per client IP, before the WAF rate-limit rule blocks."
  type        = number
  default     = 100
}

# --- EasyAuth (Entra ID sign-in on the ui app; OFF by default) ---
variable "enable_easy_auth" {
  description = "Enable EasyAuth (Entra ID) on the ui container app. Enforced on BOTH the Front Door and internal ILB paths."
  type        = bool
  default     = false
}

variable "easy_auth_client_id" {
  description = "Entra app registration (client) ID. Required when enable_easy_auth = true."
  type        = string
  default     = ""
}

variable "easy_auth_tenant_id" {
  description = "Entra tenant for EasyAuth sign-in. Empty = this subscription's tenant (single-tenant)."
  type        = string
  default     = ""
}

variable "easy_auth_client_secret" {
  description = "Entra app registration client secret. Supply via TF_VAR_easy_auth_client_secret; never commit. Required when enable_easy_auth = true."
  type        = string
  default     = ""
  sensitive   = true
}

variable "easy_auth_unauthenticated_action" {
  description = "What to do with unauthenticated callers: RedirectToLoginPage (browsers) or Return401 (pure APIs)."
  type        = string
  default     = "RedirectToLoginPage"

  validation {
    condition     = contains(["RedirectToLoginPage", "Return401"], var.easy_auth_unauthenticated_action)
    error_message = "easy_auth_unauthenticated_action must be RedirectToLoginPage or Return401."
  }
}
