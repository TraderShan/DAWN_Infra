# =====================================================================================
#  Dawn - Terraform - Key Vault (RBAC mode, private)
# -------------------------------------------------------------------------------------
#  RBAC authorization (no access policies), public network access disabled, private
#  endpoint + DNS zone group, diagnostics to Log Analytics.
# =====================================================================================

resource "azurerm_key_vault" "this" {
  name                = local.names.key_vault
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  tags                = var.tags

  tenant_id = data.azurerm_client_config.current.tenant_id
  sku_name  = "standard"

  enable_rbac_authorization  = true
  soft_delete_retention_days = 7

  public_network_access_enabled = false

  network_acls {
    bypass         = "AzureServices"
    default_action = "Deny"
  }
}

resource "azurerm_private_endpoint" "keyvault" {
  name                = "pe-${local.names.key_vault}"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  subnet_id           = azurerm_subnet.pe.id
  tags                = var.tags

  private_service_connection {
    name                           = "vault"
    private_connection_resource_id = azurerm_key_vault.this.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.zones["vault"].id]
  }
}

resource "azurerm_monitor_diagnostic_setting" "keyvault" {
  name                       = "diag-to-law"
  target_resource_id         = azurerm_key_vault.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = "allLogs"
  }

  metric {
    category = "AllMetrics"
  }
}
