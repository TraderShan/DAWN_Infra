# =====================================================================================
#  Dawn - Terraform - Azure Front Door (Premium) + WAF  ->  internal ACA "ui" app
# -------------------------------------------------------------------------------------
#  Public, WAF-protected entry to the ui app via Private Link, without exposing the
#  container app to the internet directly:
#
#    Internet -> Front Door edge -> WAF (DRS + Bot Manager + rate-limit)
#             -> Private Link (managedEnvironments) -> internal ACA env ILB -> ui app
#
#  The internal ILB path (jumpbox via the greenbay-* private DNS zone) is UNAFFECTED.
#
#  NOTE (manual step): the Private Link creates a PENDING private-endpoint connection on
#  the ACA managed environment that must be APPROVED before traffic flows. deploy.sh
#  approves it post-apply; see FRONTDOOR-EASYAUTH.md.
#
#  Requires a recent azurerm 4.x (target_type "managedEnvironments" support for ACA).
# =====================================================================================

resource "azurerm_cdn_frontdoor_profile" "this" {
  count               = var.deploy_front_door ? 1 : 0
  name                = "afd-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.this.name
  sku_name            = "Premium_AzureFrontDoor" # Premium REQUIRED for Private Link origins + managed WAF
  tags                = var.tags
}

resource "azurerm_cdn_frontdoor_endpoint" "ui" {
  count                    = var.deploy_front_door ? 1 : 0
  name                     = "ep-${local.name_prefix}"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this[0].id
  tags                     = var.tags
}

resource "azurerm_cdn_frontdoor_origin_group" "ui" {
  count                    = var.deploy_front_door ? 1 : 0
  name                     = "og-ui"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this[0].id

  load_balancing {
    sample_size                        = 4
    successful_samples_required        = 3
    additional_latency_in_milliseconds = 50
  }

  health_probe {
    path                = "/"
    request_type        = "HEAD"
    protocol            = "Https"
    interval_in_seconds = 100
  }
}

resource "azurerm_cdn_frontdoor_origin" "ui" {
  count                         = var.deploy_front_door ? 1 : 0
  name                          = "origin-ui"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.ui[0].id
  enabled                       = true

  # ui app FQDN on the internal env (external ingress = no ".internal." segment).
  host_name          = "${local.name_prefix}-ui.${azurerm_container_app_environment.this.default_domain}"
  origin_host_header = "${local.name_prefix}-ui.${azurerm_container_app_environment.this.default_domain}"
  http_port          = 80
  https_port         = 443
  priority           = 1
  weight             = 1000

  certificate_name_check_enabled = true

  # Shared Private Link to the ACA environment. Creates a PENDING connection on the env
  # that must be approved (deploy.sh does this post-apply).
  private_link {
    request_message        = "Azure Front Door Private Link to Dawn ACA (ui)"
    target_type            = "managedEnvironments"
    location               = var.location
    private_link_target_id = azurerm_container_app_environment.this.id
  }

  depends_on = [azurerm_container_app.apps]
}

resource "azurerm_cdn_frontdoor_route" "ui" {
  count                         = var.deploy_front_door ? 1 : 0
  name                          = "route-ui"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.ui[0].id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.ui[0].id
  cdn_frontdoor_origin_ids      = [azurerm_cdn_frontdoor_origin.ui[0].id]

  supported_protocols    = ["Http", "Https"]
  patterns_to_match      = ["/*"]
  forwarding_protocol    = "HttpsOnly"
  link_to_default_domain = true
  https_redirect_enabled = true # force http -> https at the edge
}

# ------------------------------- WAF policy ------------------------------------------
resource "azurerm_cdn_frontdoor_firewall_policy" "this" {
  count               = var.deploy_front_door ? 1 : 0
  name                = replace("waf${local.name_prefix}", "-", "") # WAF policy names must be alphanumeric
  resource_group_name = azurerm_resource_group.this.name
  sku_name            = "Premium_AzureFrontDoor"
  enabled             = true
  mode                = var.waf_mode # Prevention blocks; Detection only logs
  tags                = var.tags

  managed_rule {
    type    = "Microsoft_DefaultRuleSet"
    version = "2.1"
    action  = "Block"
  }

  managed_rule {
    type    = "Microsoft_BotManagerRuleSet"
    version = "1.1"
    action  = "Block"
  }

  custom_rule {
    name                           = "RateLimitPerClientIp"
    enabled                        = true
    priority                       = 100
    rate_limit_duration_in_minutes = 1
    rate_limit_threshold           = var.waf_rate_limit_threshold
    type                           = "RateLimitRule"
    action                         = "Block"

    # Count every request (every URL contains "/") toward the per-client-IP limit.
    match_condition {
      match_variable     = "RequestUri"
      operator           = "Contains"
      negation_condition = false
      match_values       = ["/"]
      transforms         = ["Lowercase"]
    }
  }
}

resource "azurerm_cdn_frontdoor_security_policy" "ui" {
  count                    = var.deploy_front_door ? 1 : 0
  name                     = "sp-ui"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this[0].id

  security_policies {
    firewall {
      cdn_frontdoor_firewall_policy_id = azurerm_cdn_frontdoor_firewall_policy.this[0].id

      association {
        domain {
          cdn_frontdoor_domain_id = azurerm_cdn_frontdoor_endpoint.ui[0].id
        }
        patterns_to_match = ["/*"]
      }
    }
  }
}
