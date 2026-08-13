# =====================================================================================
#  Dawn - Terraform - Microsoft Fabric capacity
# -------------------------------------------------------------------------------------
#  F-series capacity (tier Fabric). Administrators come from var.fabric_admin_members.
# =====================================================================================

resource "azurerm_fabric_capacity" "this" {
  name                = local.names.fabric
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  tags                = var.tags

  administration_members = var.fabric_admin_members

  sku {
    name = var.fabric_sku_name
    tier = "Fabric"
  }
}
