# =====================================================================================
#  Dawn - Terraform - Provider & version requirements
# -------------------------------------------------------------------------------------
#  Faithful translation of dawn-infra/main.bicep (+ modules/*.bicep). Private-by-design,
#  keyless, single region, 192.168.0.0/16. Consolidated (non-module) layout.
#
#  azapi is used for the Foundry account/project/connections/capabilityHost because those
#  use PREVIEW API shapes not fully modelled by azurerm - validate them at build time.
# =====================================================================================

terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # 4.56+ = registry-confirmed support for private_link.target_type = "managedEnvironments"
      # (the ACA Front Door origin in frontdoor.tf, added by PR #28239). Floor raised from ~> 4.0
      # so a plan can't resolve a pre-feature 4.x that would reject that origin. Commit the lock file.
      version = ">= 4.56, < 5.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }
  }
}
