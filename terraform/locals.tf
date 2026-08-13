# =====================================================================================
#  Dawn - Terraform - Locals (naming + role definition GUIDs)
# -------------------------------------------------------------------------------------
#  Mirrors the Bicep 'names' object. The unique suffix reproduces Bicep's
#  uniqueString(resourceGroup().id, workloadName, environmentName): a deterministic
#  13-char lowercase token derived from the resource group id + workload + environment.
# =====================================================================================

locals {
  name_prefix         = "${var.workload_name}-${var.environment_name}"
  # RG name is decoupled from the resource-name pattern on purpose; resource names below
  # still use name_prefix (dawn-poc), only the resource group is named differently.
  resource_group_name = "rg-dawn-fsi-poc"

  # 13-char deterministic suffix (uniqueString-equivalent). Lowercase hex is a valid
  # subset for storage / key vault / acr / fabric names.
  suffix = substr(sha1("${azurerm_resource_group.this.id}${var.workload_name}${var.environment_name}"), 0, 13)

  # Resource names - one-for-one with the Bicep 'names' object.
  names = {
    uami            = "id-${local.name_prefix}"
    vnet            = "vnet-${local.name_prefix}"
    bastion         = "bas-${local.name_prefix}"
    log_analytics   = "log-${local.name_prefix}"
    app_insights    = "appi-${local.name_prefix}"
    key_vault       = substr("kv${var.workload_name}${local.suffix}", 0, 24)
    storage         = substr("st${var.workload_name}${local.suffix}", 0, 24)
    cosmos          = "cosmos-${local.name_prefix}-${local.suffix}"
    search          = "srch-${local.name_prefix}-${local.suffix}"
    acr             = substr("acr${var.workload_name}${local.suffix}", 0, 50)
    foundry         = "aif-${local.name_prefix}-${local.suffix}"
    foundry_project = "proj-${local.name_prefix}"
    aca_env         = "cae-${local.name_prefix}"
    app_plan        = "plan-${local.name_prefix}"
    web_app         = "app-${local.name_prefix}-${local.suffix}"
    fabric          = substr(lower("fab${var.workload_name}${local.suffix}"), 0, 63)
  }

  # Built-in Azure role definition GUIDs (see modules/rbac.bicep).
  role_ids = {
    storage_blob_data_contributor  = "ba92f5b4-2d11-453d-a403-e96b0029c9fe"
    search_index_data_contributor  = "8ebe5a00-799e-43f5-93ac-243d3dce84a7"
    search_service_contributor     = "7ca78c08-252a-4471-8644-bb5ff32d4ba0"
    cognitive_services_openai_user = "5e0bd9bd-7b93-4f28-af87-19fc36ad61bd"
    cognitive_services_user        = "a97b65f3-24c7-4388-baec-2e87135dc908"
    key_vault_secrets_user         = "4633458b-17de-408a-b874-0445c86b69e6"
    acr_pull                       = "7f951dda-4ed3-4680-a7ca-43fe172d538d"
  }

  # Cosmos DB built-in SQL data-plane role: "Cosmos DB Built-in Data Contributor".
  cosmos_data_contributor_role_id = "00000000-0000-0000-0000-000000000002"

  # Keyed maps for for_each over the app/job lists.
  container_apps = { for a in var.container_apps : a.name => a }
  container_jobs = { for j in var.container_jobs : j.name => j }
}
