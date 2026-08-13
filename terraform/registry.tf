# =====================================================================================
#  Dawn - Terraform - Azure Container Registry (Premium, private)
# -------------------------------------------------------------------------------------
#  Admin user disabled (keyless / UAMI pull), public network access disabled, private
#  endpoint + DNS zone group, diagnostics to Log Analytics.
# =====================================================================================

resource "azurerm_container_registry" "this" {
  name                = local.names.acr
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  tags                = var.tags

  sku                           = "Premium"
  admin_enabled                 = false
  public_network_access_enabled = false
  network_rule_bypass_option    = "AzureServices"
}

resource "azurerm_private_endpoint" "acr" {
  name                = "pe-${local.names.acr}"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  subnet_id           = azurerm_subnet.pe.id
  tags                = var.tags

  private_service_connection {
    name                           = "registry"
    private_connection_resource_id = azurerm_container_registry.this.id
    subresource_names              = ["registry"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.zones["acr"].id]
  }
}

resource "azurerm_monitor_diagnostic_setting" "acr" {
  name                       = "diag-to-law"
  target_resource_id         = azurerm_container_registry.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = "allLogs"
  }

  metric {
    category = "AllMetrics"
  }
}
