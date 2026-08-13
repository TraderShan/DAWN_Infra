# =====================================================================================
#  Dawn - Terraform - EasyAuth (ACA built-in authentication, Microsoft Entra ID)
# -------------------------------------------------------------------------------------
#  Puts an Entra ID sign-in gate in front of the ui container app. Single-tenant: only
#  identities in easy_auth_tenant_id can sign in. Enforced at ingress on EVERY path
#  (Front Door AND the internal ILB), so a token-less curl from the jumpbox gets a
#  401/redirect once this is on.
#
#  azurerm_container_app has no auth-config argument, so the authConfig child resource is
#  created with azapi (same provider already used for the Foundry preview shapes). The
#  client secret itself is added to the ui app as a container-app secret in compute.tf.
#
#  Prerequisite (manual): an Entra app registration (client id + secret) whose redirect
#  URI is https://<front-door-host>/.auth/login/aad/callback. See FRONTDOOR-EASYAUTH.md.
# =====================================================================================

locals {
  # Default to this subscription's tenant (MCAPS) when no tenant is given -> single-tenant.
  easy_auth_tenant_id = coalesce(var.easy_auth_tenant_id, data.azurerm_client_config.current.tenant_id)
}

resource "azapi_resource" "ui_auth" {
  count     = var.enable_easy_auth ? 1 : 0
  type      = "Microsoft.App/containerApps/authConfigs@2024-03-01"
  name      = "current"
  parent_id = azurerm_container_app.apps["ui"].id

  body = {
    properties = {
      platform = {
        enabled = true
      }
      globalValidation = {
        unauthenticatedClientAction = var.easy_auth_unauthenticated_action
        redirectToProvider          = "azureactivedirectory"
      }
      identityProviders = {
        azureActiveDirectory = {
          enabled = true
          registration = {
            openIdIssuer            = "https://login.microsoftonline.com/${local.easy_auth_tenant_id}/v2.0"
            clientId                = var.easy_auth_client_id
            clientSecretSettingName = "aad-client-secret" # matches the secret added in compute.tf
          }
          validation = {
            # Accept both the bare client id (audience of the id_token from the interactive
            # login flow) and the api:// form (audience of access tokens issued to the app).
            allowedAudiences = [var.easy_auth_client_id, "api://${var.easy_auth_client_id}"]
          }
        }
      }
      login = {
        preserveUrlFragmentsForLogins = false
        tokenStore = {
          enabled = false # no token-store storage wired for the POC; enable + back with blob later
        }
      }
    }
  }

  # The secret must exist on the app before the authConfig references it.
  depends_on = [azurerm_container_app.apps]
}
