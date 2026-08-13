# =====================================================================================
#  Dawn - Terraform - Data stores (Storage, Cosmos DB, AI Search)
# -------------------------------------------------------------------------------------
#  All keyless (managed identity + RBAC only), public network access disabled, each with
#  a private endpoint + private DNS zone group and diagnostics to Log Analytics.
#  Cosmos = NoSQL serverless with the Dawn read-model / artifact / conversation
#  containers. Data-plane RBAC is applied centrally in rbac.tf.
# =====================================================================================

# ------------------------------- Storage (keyless) -----------------------------------
resource "azurerm_storage_account" "this" {
  name                = local.names.storage
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  tags                = var.tags

  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false # allowBlobPublicAccess: false
  shared_access_key_enabled       = false # keyless
  public_network_access_enabled   = false

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }
}

resource "azurerm_private_endpoint" "storage_blob" {
  name                = "pe-${local.names.storage}-blob"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  subnet_id           = azurerm_subnet.pe.id
  tags                = var.tags

  private_service_connection {
    name                           = "blob"
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.zones["blob"].id]
  }
}

# Account-level diagnostics: metrics only (Transaction), matching the Bicep.
resource "azurerm_monitor_diagnostic_setting" "storage_account" {
  name                       = "diag-to-law"
  target_resource_id         = azurerm_storage_account.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  metric {
    category = "Transaction"
  }
}

# Blob service diagnostics: allLogs + Transaction metrics.
resource "azurerm_monitor_diagnostic_setting" "storage_blob" {
  name                       = "diag-to-law"
  target_resource_id         = "${azurerm_storage_account.this.id}/blobServices/default"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = "allLogs"
  }

  metric {
    category = "Transaction"
  }
}

# ------------------------------- Cosmos DB (NoSQL, serverless, keyless) ---------------
resource "azurerm_cosmosdb_account" "this" {
  name                = local.names.cosmos
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  tags                = var.tags

  offer_type = "Standard"
  kind       = "GlobalDocumentDB"

  local_authentication_disabled = true
  public_network_access_enabled = false
  automatic_failover_enabled    = false

  capabilities {
    name = "EnableServerless"
  }

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = var.location
    failover_priority = 0
    zone_redundant    = false
  }
}

resource "azurerm_cosmosdb_sql_database" "dawn" {
  name                = "dawn"
  resource_group_name = azurerm_resource_group.this.name
  account_name        = azurerm_cosmosdb_account.this.name
}

# Containers + partition keys from modules/cosmos.bicep.
locals {
  cosmos_containers = {
    accounts      = "/accountId"
    opportunities = "/accountId"
    calls         = "/accountId"
    signals       = "/accountId"
    artifacts     = "/forDate"   # brief + ranking artifacts (dated, versioned)
    conversations = "/sessionId" # app-managed memory (if not Foundry-managed)
  }
}

resource "azurerm_cosmosdb_sql_container" "containers" {
  for_each            = local.cosmos_containers
  name                = each.key
  resource_group_name = azurerm_resource_group.this.name
  account_name        = azurerm_cosmosdb_account.this.name
  database_name       = azurerm_cosmosdb_sql_database.dawn.name
  partition_key_paths = [each.value]
}

resource "azurerm_private_endpoint" "cosmos" {
  name                = "pe-${local.names.cosmos}"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  subnet_id           = azurerm_subnet.pe.id
  tags                = var.tags

  private_service_connection {
    name                           = "cosmos"
    private_connection_resource_id = azurerm_cosmosdb_account.this.id
    subresource_names              = ["Sql"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.zones["cosmos"].id]
  }
}

resource "azurerm_monitor_diagnostic_setting" "cosmos" {
  name                       = "diag-to-law"
  target_resource_id         = azurerm_cosmosdb_account.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = "allLogs"
  }

  metric {
    category = "Requests"
  }
}

# ------------------------------- AI Search (keyless) ---------------------------------
resource "azurerm_search_service" "this" {
  name                = local.names.search
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  tags                = var.tags

  sku             = var.search_sku
  replica_count   = 1
  partition_count = 1

  local_authentication_enabled  = false # keyless
  public_network_access_enabled = false
  semantic_search_sku           = "free"

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_private_endpoint" "search" {
  name                = "pe-${local.names.search}"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  subnet_id           = azurerm_subnet.pe.id
  tags                = var.tags

  private_service_connection {
    name                           = "search"
    private_connection_resource_id = azurerm_search_service.this.id
    subresource_names              = ["searchService"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.zones["search"].id]
  }
}

resource "azurerm_monitor_diagnostic_setting" "search" {
  name                       = "diag-to-law"
  target_resource_id         = azurerm_search_service.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = "allLogs"
  }

  metric {
    category = "AllMetrics"
  }
}
