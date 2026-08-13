# =====================================================================================
#  Microsoft Defender for Cloud - subscription-scoped plan enablement (self-contained)
# -------------------------------------------------------------------------------------
#  DELIBERATELY SEPARATE from the main infra (own state): Defender plans apply to the
#  WHOLE subscription, not just the Dawn resource group. See README.md for cost/backout.
#
#  Deploy:
#    export ARM_SUBSCRIPTION_ID=3a8f035c-5882-4df8-90f7-eb11a8bda066
#    terraform init && terraform apply
#  Back out:
#    terraform destroy   # reverts every plan to Free and removes the contact
# =====================================================================================

terraform {
  required_version = ">= 1.5"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "security_contact_email" {
  description = "Optional email for Defender alert notifications. Empty = skip the contact."
  type        = string
  default     = ""
}

locals {
  # resource_type => subplan ("" = no subplan)
  plans = {
    VirtualMachines = "P2"                  # Defender for Servers (jumpbox); "P1" is cheaper
    StorageAccounts = "DefenderForStorageV2" # Defender for Storage
    KeyVaults       = ""                     # Defender for Key Vault
    CosmosDbs       = ""                     # Defender for Cosmos DB
    Containers      = ""                     # Defender for Containers (ACR image scanning)
    Arm             = ""                     # Defender for Resource Manager
    # AI = ""                                # Defender for AI Services (Foundry). NEWER plan - the
    #                                          azurerm provider may not accept "AI" yet. If so, enable via:
    #                                          az security pricing create -n AI --tier Standard
  }
}

resource "azurerm_security_center_subscription_pricing" "plan" {
  for_each      = local.plans
  tier          = "Standard"
  resource_type = each.key
  subplan       = each.value != "" ? each.value : null
}

resource "azurerm_security_center_contact" "this" {
  count               = var.security_contact_email != "" ? 1 : 0
  name                = "default"
  email               = var.security_contact_email
  alert_notifications = true
  alerts_to_admins    = true
}

output "enabled_plans" {
  value = keys(local.plans)
}
