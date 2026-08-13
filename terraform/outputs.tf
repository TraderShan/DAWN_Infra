# =====================================================================================
#  Dawn - Terraform - Outputs (mirror of main.bicep outputs)
# =====================================================================================

output "managed_identity_client_id" {
  description = "Client id of the shared user-assigned managed identity."
  value       = azurerm_user_assigned_identity.this.client_id
}

output "vnet_id" {
  description = "Resource id of the spoke VNet."
  value       = azurerm_virtual_network.this.id
}

output "bastion_name" {
  description = "Bastion host name (empty when Bastion is not deployed)."
  value       = var.deploy_bastion ? azurerm_bastion_host.this[0].name : ""
}

output "jumpbox_name" {
  description = "Jumpbox VM name (empty when the jumpbox is not deployed)."
  value       = var.deploy_jumpbox ? azurerm_windows_virtual_machine.jumpbox[0].name : ""
}

output "jumpbox_private_ip" {
  description = "Jumpbox private IP (empty when the jumpbox is not deployed)."
  value       = var.deploy_jumpbox ? azurerm_network_interface.jumpbox[0].private_ip_address : ""
}

output "app_insights_connection_string" {
  description = "Application Insights connection string."
  value       = azurerm_application_insights.this.connection_string
  sensitive   = true
}

output "foundry_account_name" {
  description = "Azure AI Foundry account name."
  value       = azapi_resource.foundry.name
}

output "foundry_endpoint" {
  description = "Azure AI Foundry account endpoint."
  value       = azapi_resource.foundry.output.properties.endpoint
}

output "foundry_project_name" {
  description = "Azure AI Foundry project name."
  value       = azapi_resource.project.name
}

output "search_endpoint" {
  description = "Azure AI Search endpoint."
  value       = "https://${azurerm_search_service.this.name}.search.windows.net"
}

output "cosmos_endpoint" {
  description = "Cosmos DB document endpoint."
  value       = azurerm_cosmosdb_account.this.endpoint
}

output "cosmos_database_name" {
  description = "Cosmos DB application database name."
  value       = azurerm_cosmosdb_sql_database.dawn.name
}

output "storage_account_name" {
  description = "Storage account name."
  value       = azurerm_storage_account.this.name
}

output "key_vault_name" {
  description = "Key Vault name."
  value       = azurerm_key_vault.this.name
}

output "acr_login_server" {
  description = "Azure Container Registry login server."
  value       = azurerm_container_registry.this.login_server
}

output "aca_environment_name" {
  description = "Azure Container Apps environment name."
  value       = azurerm_container_app_environment.this.name
}

output "fabric_capacity_name" {
  description = "Microsoft Fabric capacity name."
  value       = azurerm_fabric_capacity.this.name
}

output "front_door_endpoint_host_name" {
  description = "Public Front Door hostname for the ui app (empty when deploy_front_door = false). Browse https://<this>."
  value       = var.deploy_front_door ? azurerm_cdn_frontdoor_endpoint.ui[0].host_name : ""
}
