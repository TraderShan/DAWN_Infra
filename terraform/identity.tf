# =====================================================================================
#  Dawn - Terraform - User-assigned managed identity
# -------------------------------------------------------------------------------------
#  Shared identity used for keyless RBAC across the stack (ACR pull, data-plane access).
# =====================================================================================

resource "azurerm_user_assigned_identity" "this" {
  name                = local.names.uami
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  tags                = var.tags
}
