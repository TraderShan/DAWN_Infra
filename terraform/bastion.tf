# =====================================================================================
#  Dawn - Terraform - Azure Bastion (secure access path; no public workload ingress)
# -------------------------------------------------------------------------------------
#  Standard public IP fronts the Bastion host only; workloads stay private and are
#  reached through Bastion over TLS. Gated on var.deploy_bastion.
# =====================================================================================

resource "azurerm_public_ip" "bastion" {
  count               = var.deploy_bastion ? 1 : 0
  name                = "pip-${local.names.bastion}"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  sku                 = "Standard"
  allocation_method   = "Static"
  tags                = var.tags
}

resource "azurerm_bastion_host" "this" {
  count               = var.deploy_bastion ? 1 : 0
  name                = local.names.bastion
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  sku                 = var.bastion_sku
  tags                = var.tags

  # Native-client support (az network bastion rdp/tunnel). Requires Standard SKU.
  tunneling_enabled = var.bastion_sku == "Standard"

  ip_configuration {
    name                 = "ipconfig"
    subnet_id            = azurerm_subnet.bastion.id
    public_ip_address_id = azurerm_public_ip.bastion[0].id
  }
}

resource "azurerm_monitor_diagnostic_setting" "bastion" {
  count                      = var.deploy_bastion ? 1 : 0
  name                       = "diag-to-law"
  target_resource_id         = azurerm_bastion_host.this[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = "allLogs"
  }

  metric {
    category = "AllMetrics"
  }
}
