# =====================================================================================
#  Dawn - Terraform - Providers
# -------------------------------------------------------------------------------------
#  azurerm for the bulk of the stack; azapi for the preview Foundry shapes.
# =====================================================================================

provider "azurerm" {
  features {}
}

provider "azapi" {}

# Current subscription / tenant context. Used for the Key Vault tenant id and for
# building subscription-scoped role definition ids in rbac.tf.
data "azurerm_client_config" "current" {}
