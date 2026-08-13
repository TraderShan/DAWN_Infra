# =====================================================================================
#  Dawn - Terraform - Observability (Log Analytics + workspace-based App Insights)
# -------------------------------------------------------------------------------------
#  Telemetry ingestion stays on public endpoints (private AMPLS is overkill for a POC).
# =====================================================================================

resource "azurerm_log_analytics_workspace" "this" {
  name                = local.names.log_analytics
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

resource "azurerm_application_insights" "this" {
  name                = local.names.app_insights
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  application_type    = "web"
  workspace_id        = azurerm_log_analytics_workspace.this.id

  internet_ingestion_enabled = true
  internet_query_enabled     = true

  tags = var.tags
}
