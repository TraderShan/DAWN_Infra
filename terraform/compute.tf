# =====================================================================================
#  Dawn - Terraform - Compute (ACA environment + apps + jobs, optional Web App)
# -------------------------------------------------------------------------------------
#  Internal (no public ingress) ACA environment, VNet-integrated on snet-aca. Each app
#  pulls from ACR with the shared UAMI and gets the App Insights connection string. Jobs
#  run in the same internal environment. All compute depends_on the RBAC assignments so
#  ACR pull / data-plane access is in place before the workloads start.
# =====================================================================================

# ------------------------------- ACA environment (internal) --------------------------
resource "azurerm_container_app_environment" "this" {
  name                = local.names.aca_env
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  tags                = var.tags

  log_analytics_workspace_id     = azurerm_log_analytics_workspace.this.id
  infrastructure_subnet_id       = azurerm_subnet.aca.id
  internal_load_balancer_enabled = true # internal = true: no public ingress
  zone_redundant                 = false

  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }
}

resource "azurerm_monitor_diagnostic_setting" "aca_env" {
  name                       = "diag-to-law"
  target_resource_id         = azurerm_container_app_environment.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = "allLogs"
  }
}

# ------------------------------- ACA Private DNS zone --------------------------------
# Internal environments don't auto-create a DNS zone; without this, app FQDNs
# (<app>.<defaultDomain>) won't resolve from inside the VNet. With external ingress
# (external_enabled = true) the FQDN has no ".internal.", so a single "*" wildcard covers all.
resource "azurerm_private_dns_zone" "aca" {
  name                = azurerm_container_app_environment.this.default_domain
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_private_dns_a_record" "aca_wildcard" {
  name                = "*"
  zone_name           = azurerm_private_dns_zone.aca.name
  resource_group_name = azurerm_resource_group.this.name
  ttl                 = 3600
  records             = [azurerm_container_app_environment.this.static_ip_address]
}

resource "azurerm_private_dns_zone_virtual_network_link" "aca" {
  name                  = "link-${local.names.vnet}"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name  = azurerm_private_dns_zone.aca.name
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false
  tags                  = var.tags
}

# ------------------------------- Container apps --------------------------------------
resource "azurerm_container_app" "apps" {
  for_each = local.container_apps

  name                         = "${local.name_prefix}-${each.value.name}"
  resource_group_name          = azurerm_resource_group.this.name
  container_app_environment_id = azurerm_container_app_environment.this.id
  revision_mode                = "Single"
  tags                         = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.this.id]
  }

  registry {
    server   = azurerm_container_registry.this.login_server
    identity = azurerm_user_assigned_identity.this.id
  }

  # EasyAuth client secret — added only to the ui app when EasyAuth is enabled. The
  # authConfig (easyauth.tf) references it by name ("aad-client-secret").
  dynamic "secret" {
    for_each = (var.enable_easy_auth && each.value.name == "ui") ? [1] : []
    content {
      name  = "aad-client-secret"
      value = var.easy_auth_client_secret
    }
  }

  dynamic "ingress" {
    for_each = each.value.ingress_enabled ? [1] : []
    content {
      # external_enabled = true on an INTERNAL environment = reachable from the VNet via the
      # internal load balancer (still private, not internet-facing). false = env-internal only.
      external_enabled = true
      target_port      = each.value.target_port
      transport        = "auto"

      traffic_weight {
        percentage      = 100
        latest_revision = true
      }
    }
  }

  template {
    min_replicas = 1
    max_replicas = 3

    container {
      name   = each.value.name
      image  = (each.value.image != null && each.value.image != "") ? each.value.image : var.placeholder_image
      cpu    = 0.5
      memory = "1Gi"

      env {
        name  = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        value = azurerm_application_insights.this.connection_string
      }
    }
  }

  depends_on = [
    azurerm_role_assignment.acr_uami,
    azurerm_role_assignment.storage_uami,
    azurerm_role_assignment.search_data_uami,
    azurerm_role_assignment.openai_uami,
    azurerm_role_assignment.vault_uami,
    azurerm_cosmosdb_sql_role_assignment.uami,
  ]
}

# ------------------------------- Container jobs --------------------------------------
resource "azurerm_container_app_job" "jobs" {
  for_each = local.container_jobs

  name                         = "${local.name_prefix}-${each.value.name}"
  resource_group_name          = azurerm_resource_group.this.name
  location                     = var.location
  container_app_environment_id = azurerm_container_app_environment.this.id
  tags                         = var.tags

  replica_timeout_in_seconds = 3600
  replica_retry_limit        = 1

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.this.id]
  }

  registry {
    server   = azurerm_container_registry.this.login_server
    identity = azurerm_user_assigned_identity.this.id
  }

  dynamic "schedule_trigger_config" {
    for_each = each.value.trigger_type == "Schedule" ? [1] : []
    content {
      # Default 09:00 UTC (~5am US Eastern) when no cron is supplied.
      cron_expression          = (each.value.cron != null && each.value.cron != "") ? each.value.cron : "0 9 * * *"
      parallelism              = 1
      replica_completion_count = 1
    }
  }

  dynamic "manual_trigger_config" {
    for_each = each.value.trigger_type == "Schedule" ? [] : [1]
    content {
      parallelism              = 1
      replica_completion_count = 1
    }
  }

  template {
    container {
      name   = each.value.name
      image  = (each.value.image != null && each.value.image != "") ? each.value.image : var.placeholder_image
      cpu    = 0.5
      memory = "1Gi"

      env {
        name  = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        value = azurerm_application_insights.this.connection_string
      }
    }
  }

  depends_on = [
    azurerm_role_assignment.acr_uami,
    azurerm_role_assignment.storage_uami,
    azurerm_role_assignment.search_data_uami,
    azurerm_role_assignment.openai_uami,
    azurerm_role_assignment.vault_uami,
    azurerm_cosmosdb_sql_role_assignment.uami,
  ]
}

# ------------------------------- Optional Web App (OFF by default) --------------------
#  Kept private even when enabled (public_network_access_enabled = false). The docker
#  image is split from var.placeholder_image assuming the MCR registry.
locals {
  webapp_docker_registry_url = "https://mcr.microsoft.com"
  webapp_docker_image_name   = replace(var.placeholder_image, "mcr.microsoft.com/", "")
}

resource "azurerm_service_plan" "web" {
  count               = var.deploy_web_app ? 1 : 0
  name                = local.names.app_plan
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  os_type             = "Linux"
  sku_name            = var.app_service_plan_sku
  tags                = var.tags
}

resource "azurerm_linux_web_app" "web" {
  count               = var.deploy_web_app ? 1 : 0
  name                = local.names.web_app
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  service_plan_id     = azurerm_service_plan.web[0].id
  tags                = var.tags

  https_only                      = true
  virtual_network_subnet_id       = azurerm_subnet.appsvc.id
  public_network_access_enabled   = false
  key_vault_reference_identity_id = azurerm_user_assigned_identity.this.id

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.this.id]
  }

  site_config {
    ftps_state          = "Disabled"
    minimum_tls_version = "1.2"

    container_registry_use_managed_identity       = true
    container_registry_managed_identity_client_id = azurerm_user_assigned_identity.this.client_id

    application_stack {
      docker_registry_url = local.webapp_docker_registry_url
      docker_image_name   = local.webapp_docker_image_name
    }
  }

  app_settings = {
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.this.connection_string
    WEBSITES_PORT                         = "80"
    WEBSITE_VNET_ROUTE_ALL                = "1" # vnetRouteAllEnabled: true
  }

  depends_on = [
    azurerm_role_assignment.acr_uami,
    azurerm_role_assignment.vault_uami,
  ]
}

resource "azurerm_monitor_diagnostic_setting" "webapp_site" {
  count                      = var.deploy_web_app ? 1 : 0
  name                       = "diag-to-law"
  target_resource_id         = azurerm_linux_web_app.web[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = "allLogs"
  }

  metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "webapp_plan" {
  count                      = var.deploy_web_app ? 1 : 0
  name                       = "diag-to-law"
  target_resource_id         = azurerm_service_plan.web[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  metric {
    category = "AllMetrics"
  }
}
