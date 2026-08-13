# =====================================================================================
#  Dawn - Terraform - Azure AI Foundry (account + project + connections + capability host)
# -------------------------------------------------------------------------------------
#  AIServices account with a custom subdomain, public access disabled, local auth
#  disabled, project management enabled, and network injection into the agent subnet so
#  hosted-agent + tool traffic stays on the VNet. The project owns three BYO (AAD)
#  connections (Cosmos thread store, Storage file store, AI Search vectors).
#
#  The capability host is a SEPARATE resource and depends_on the RBAC role assignments,
#  mirroring the Bicep ordering (capability-host-before-RBAC is a known runtime failure).
#
#  NOTE: the account (kind=AIServices), project, connections, and capabilityHosts use
#  PREVIEW API shapes (2025-06-01 / 2025-04-01-preview) that azurerm does not fully model
#  - they are provisioned via azapi and schema validation is disabled. These preview API
#  shapes MUST be validated at build time.
# =====================================================================================

# ------------------------------- Foundry account ------------------------------------
resource "azapi_resource" "foundry" {
  type      = "Microsoft.CognitiveServices/accounts@2025-06-01"
  name      = local.names.foundry
  parent_id = azurerm_resource_group.this.id
  location  = var.location
  tags      = var.tags

  schema_validation_enabled = false # preview shape - validate at build time

  identity {
    type = "SystemAssigned"
  }

  body = {
    kind = "AIServices"
    sku = {
      name = "S0"
    }
    properties = {
      customSubDomainName    = local.names.foundry
      publicNetworkAccess    = "Disabled"
      disableLocalAuth       = true
      allowProjectManagement = true
      networkAcls = {
        defaultAction = "Deny"
        bypass        = "AzureServices"
      }
      networkInjections = [
        {
          scenario                   = "agent"
          subnetArmId                = azurerm_subnet.agent.id
          useMicrosoftManagedNetwork = false
        }
      ]
    }
  }

  response_export_values = ["properties.endpoint", "identity.principalId"]
}

# ------------------------------- Foundry project ------------------------------------
resource "azapi_resource" "project" {
  type      = "Microsoft.CognitiveServices/accounts/projects@2025-06-01"
  name      = local.names.foundry_project
  parent_id = azapi_resource.foundry.id
  location  = var.location
  tags      = var.tags

  schema_validation_enabled = false # preview shape - validate at build time

  identity {
    type = "SystemAssigned"
  }

  body = {
    properties = {
      displayName = "Dawn Agent Project"
      description = "Foundry project for the Dawn overnight agents + Ask Dawn (MAF hosted agents)."
    }
  }

  response_export_values = ["identity.principalId"]
}

# ------------------------------- Optional model deployments --------------------------
resource "azapi_resource" "chat_model" {
  count = var.deploy_model ? 1 : 0

  type      = "Microsoft.CognitiveServices/accounts/deployments@2025-06-01"
  name      = var.chat_model_deployment_name
  parent_id = azapi_resource.foundry.id

  schema_validation_enabled = false

  body = {
    sku = {
      name     = var.model_sku_name
      capacity = var.chat_model_capacity
    }
    properties = {
      model = {
        format  = "OpenAI"
        name    = var.chat_model_name
        version = var.chat_model_version
      }
    }
  }
}

resource "azapi_resource" "embedding_model" {
  count = var.deploy_embedding_model ? 1 : 0

  type      = "Microsoft.CognitiveServices/accounts/deployments@2025-06-01"
  name      = var.embedding_deployment_name
  parent_id = azapi_resource.foundry.id

  schema_validation_enabled = false

  body = {
    sku = {
      name     = var.model_sku_name
      capacity = var.embedding_capacity
    }
    properties = {
      model = {
        format  = "OpenAI"
        name    = var.embedding_model_name
        version = var.embedding_model_version
      }
    }
  }

  # Serialize deployments (mirrors the Bicep dependsOn: chatModel).
  depends_on = [azapi_resource.chat_model]
}

# ------------------------------- Project connections (BYO, AAD) ----------------------
resource "azapi_resource" "cosmos_connection" {
  count     = var.agent_stack_deployed ? 0 : 1 # skip on redeploy — caphost locks these
  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name      = "cosmos-thread-store"
  parent_id = azapi_resource.project.id

  schema_validation_enabled = false # preview shape - validate at build time

  body = {
    properties = {
      category      = "CosmosDB"
      target        = azurerm_cosmosdb_account.this.endpoint
      authType      = "AAD"
      isSharedToAll = true
      metadata = {
        ApiType    = "Azure"
        ResourceId = azurerm_cosmosdb_account.this.id
        location   = var.location
      }
    }
  }
}

resource "azapi_resource" "storage_connection" {
  count     = var.agent_stack_deployed ? 0 : 1 # skip on redeploy — caphost locks these
  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name      = "storage-file-store"
  parent_id = azapi_resource.project.id

  schema_validation_enabled = false # preview shape - validate at build time

  body = {
    properties = {
      category      = "AzureStorageAccount"
      target        = azurerm_storage_account.this.primary_blob_endpoint
      authType      = "AAD"
      isSharedToAll = true
      metadata = {
        ApiType    = "Azure"
        ResourceId = azurerm_storage_account.this.id
        location   = var.location
      }
    }
  }
}

resource "azapi_resource" "search_connection" {
  count     = var.agent_stack_deployed ? 0 : 1 # skip on redeploy — caphost locks these
  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name      = "aisearch-knowledge"
  parent_id = azapi_resource.project.id

  schema_validation_enabled = false # preview shape - validate at build time

  body = {
    properties = {
      category      = "CognitiveSearch"
      target        = "https://${local.names.search}.search.windows.net"
      authType      = "AAD"
      isSharedToAll = true
      metadata = {
        ApiType    = "Azure"
        ResourceId = azurerm_search_service.this.id
        location   = var.location
      }
    }
  }
}

# ------------------------------- Account private endpoint (3 zones) ------------------
resource "azurerm_private_endpoint" "foundry" {
  name                = "pe-${local.names.foundry}"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  subnet_id           = azurerm_subnet.pe.id
  tags                = var.tags

  private_service_connection {
    name                           = "account"
    private_connection_resource_id = azapi_resource.foundry.id
    subresource_names              = ["account"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "default"
    private_dns_zone_ids = [
      azurerm_private_dns_zone.zones["openai"].id,
      azurerm_private_dns_zone.zones["cognitive"].id,
      azurerm_private_dns_zone.zones["aiservices"].id,
    ]
  }
}

resource "azurerm_monitor_diagnostic_setting" "foundry" {
  name                       = "diag-to-law"
  target_resource_id         = azapi_resource.foundry.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = "allLogs"
  }

  metric {
    category = "AllMetrics"
  }
}

# ------------------------------- Capability host (AFTER RBAC) ------------------------
#  Deliberately depends_on the RBAC role assignments so the project's managed identity
#  already holds its data-plane roles when the capability host binds the connections.
resource "azapi_resource" "capability_host" {
  count     = var.agent_stack_deployed ? 0 : 1 # skip on redeploy — already exists
  type      = "Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-04-01-preview"
  name      = "agents-capability-host"
  parent_id = azapi_resource.project.id

  schema_validation_enabled = false # preview shape - validate at build time

  # Literal connection names (not resource references) so this stays valid when the
  # connections are count-gated out on redeploy.
  body = {
    properties = {
      capabilityHostKind       = "Agents"
      threadStorageConnections = ["cosmos-thread-store"]
      storageConnections       = ["storage-file-store"]
      vectorStoreConnections   = ["aisearch-knowledge"]
    }
  }

  depends_on = [
    azapi_resource.cosmos_connection,
    azapi_resource.storage_connection,
    azapi_resource.search_connection,
    azurerm_role_assignment.storage_uami,
    azurerm_role_assignment.storage_project,
    azurerm_role_assignment.search_data_uami,
    azurerm_role_assignment.search_service_project,
    azurerm_role_assignment.search_data_project,
    azurerm_role_assignment.openai_uami,
    azurerm_role_assignment.vault_uami,
    azurerm_role_assignment.acr_uami,
    azurerm_cosmosdb_sql_role_assignment.project,
    azurerm_cosmosdb_sql_role_assignment.uami,
    azurerm_role_assignment.cosmos_operator_project,
  ]
}
