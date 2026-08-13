# =====================================================================================
#  Dawn - Terraform - Centralized keyless RBAC
# -------------------------------------------------------------------------------------
#  Grants the UAMI and the Foundry project's managed identity the data-plane roles they
#  need, scoped to each target resource. Cosmos uses data-plane SQL role assignments.
#  Optional tester assignments are guarded by var.tester_principal_id.
#
#  skip_service_principal_aad_check avoids transient failures assigning roles to the
#  freshly-created project / user-assigned identities before they replicate in Entra.
# =====================================================================================

locals {
  role_scope_prefix = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions"
}

# ---- Storage Blob Data Contributor: UAMI + Foundry project ----
resource "azurerm_role_assignment" "storage_uami" {
  scope                            = azurerm_storage_account.this.id
  role_definition_id               = "${local.role_scope_prefix}/${local.role_ids.storage_blob_data_contributor}"
  principal_id                     = azurerm_user_assigned_identity.this.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "storage_project" {
  scope                            = azurerm_storage_account.this.id
  role_definition_id               = "${local.role_scope_prefix}/${local.role_ids.storage_blob_data_contributor}"
  principal_id                     = azapi_resource.project.output.identity.principalId
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

# ---- AI Search: data + service contributor for UAMI + Foundry project ----
resource "azurerm_role_assignment" "search_data_uami" {
  scope                            = azurerm_search_service.this.id
  role_definition_id               = "${local.role_scope_prefix}/${local.role_ids.search_index_data_contributor}"
  principal_id                     = azurerm_user_assigned_identity.this.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "search_service_project" {
  scope                            = azurerm_search_service.this.id
  role_definition_id               = "${local.role_scope_prefix}/${local.role_ids.search_service_contributor}"
  principal_id                     = azapi_resource.project.output.identity.principalId
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "search_data_project" {
  scope                            = azurerm_search_service.this.id
  role_definition_id               = "${local.role_scope_prefix}/${local.role_ids.search_index_data_contributor}"
  principal_id                     = azapi_resource.project.output.identity.principalId
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

# ---- Foundry account: Cognitive Services OpenAI User for the UAMI ----
resource "azurerm_role_assignment" "openai_uami" {
  scope                            = azapi_resource.foundry.id
  role_definition_id               = "${local.role_scope_prefix}/${local.role_ids.cognitive_services_openai_user}"
  principal_id                     = azurerm_user_assigned_identity.this.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

# ---- Key Vault Secrets User: UAMI ----
resource "azurerm_role_assignment" "vault_uami" {
  scope                            = azurerm_key_vault.this.id
  role_definition_id               = "${local.role_scope_prefix}/${local.role_ids.key_vault_secrets_user}"
  principal_id                     = azurerm_user_assigned_identity.this.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

# ---- AcrPull: UAMI ----
resource "azurerm_role_assignment" "acr_uami" {
  scope                            = azurerm_container_registry.this.id
  role_definition_id               = "${local.role_scope_prefix}/${local.role_ids.acr_pull}"
  principal_id                     = azurerm_user_assigned_identity.this.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

# ---- Cosmos DB data-plane (Built-in Data Contributor): Foundry project + UAMI ----
resource "azurerm_cosmosdb_sql_role_assignment" "project" {
  resource_group_name = azurerm_resource_group.this.name
  account_name        = azurerm_cosmosdb_account.this.name
  role_definition_id  = "${azurerm_cosmosdb_account.this.id}/sqlRoleDefinitions/${local.cosmos_data_contributor_role_id}"
  principal_id        = azapi_resource.project.output.identity.principalId
  scope               = azurerm_cosmosdb_account.this.id
}

resource "azurerm_cosmosdb_sql_role_assignment" "uami" {
  resource_group_name = azurerm_resource_group.this.name
  account_name        = azurerm_cosmosdb_account.this.name
  role_definition_id  = "${azurerm_cosmosdb_account.this.id}/sqlRoleDefinitions/${local.cosmos_data_contributor_role_id}"
  principal_id        = azurerm_user_assigned_identity.this.principal_id
  scope               = azurerm_cosmosdb_account.this.id
}

# ---- Cosmos DB CONTROL-plane (Cosmos DB Operator): Foundry project ----
# Required so the capability host can create the 'enterprise_memory' database + containers
# the Agents runtime provisions. Without it, the capability host fails with a missing
# 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/read' authorization.
resource "azurerm_role_assignment" "cosmos_operator_project" {
  scope                            = azurerm_cosmosdb_account.this.id
  role_definition_name             = "Cosmos DB Operator"
  principal_id                     = azapi_resource.project.output.identity.principalId
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

# ---- Optional tester (hands-on data access) ----
resource "azurerm_role_assignment" "storage_tester" {
  count              = var.tester_principal_id != "" ? 1 : 0
  scope              = azurerm_storage_account.this.id
  role_definition_id = "${local.role_scope_prefix}/${local.role_ids.storage_blob_data_contributor}"
  principal_id       = var.tester_principal_id
  principal_type     = "User"
}

resource "azurerm_role_assignment" "openai_tester" {
  count              = var.tester_principal_id != "" ? 1 : 0
  scope              = azapi_resource.foundry.id
  role_definition_id = "${local.role_scope_prefix}/${local.role_ids.cognitive_services_user}"
  principal_id       = var.tester_principal_id
  principal_type     = "User"
}
