# =====================================================================================
#  Dawn - Terraform - Network (RG + spoke VNet + 5 subnets + 8 private DNS zones)
# -------------------------------------------------------------------------------------
#  Address space 192.168.0.0/16. Agent + ACA subnets delegated to Microsoft.App/
#  environments; snet-appsvc delegated to Microsoft.Web/serverFarms; snet-pe has private
#  endpoint network policies disabled; AzureBastionSubnet is a plain /26.
# =====================================================================================

resource "azurerm_resource_group" "this" {
  name     = local.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "this" {
  name                = local.names.vnet
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = [var.vnet_address_prefix]
  tags                = var.tags
}

# snet-agent -> Microsoft.App/environments (Foundry hosted agents / network injection)
resource "azurerm_subnet" "agent" {
  name                 = "snet-agent"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.agent_subnet_prefix]

  delegation {
    name = "agent-delegation"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# snet-pe -> private endpoints (PE network policies disabled)
resource "azurerm_subnet" "pe" {
  name                              = "snet-pe"
  resource_group_name               = azurerm_resource_group.this.name
  virtual_network_name              = azurerm_virtual_network.this.name
  address_prefixes                  = [var.pe_subnet_prefix]
  private_endpoint_network_policies = "Disabled"
}

# snet-aca -> Microsoft.App/environments (ACA workloads)
resource "azurerm_subnet" "aca" {
  name                 = "snet-aca"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.aca_subnet_prefix]

  delegation {
    name = "aca-delegation"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# AzureBastionSubnet (fixed name, /26)
resource "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.bastion_subnet_prefix]
}

# snet-appsvc -> Microsoft.Web/serverFarms (optional Web App)
resource "azurerm_subnet" "appsvc" {
  name                 = "snet-appsvc"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.appsvc_subnet_prefix]

  delegation {
    name = "appsvc-delegation"
    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

# snet-mgmt -> undelegated; hosts the optional jumpbox VM (Bastion target)
resource "azurerm_subnet" "mgmt" {
  name                 = "snet-mgmt"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.mgmt_subnet_prefix]
}

# --- Private DNS zones (8) + VNet links ---
# blob uses the public-cloud storage suffix (privatelink.blob.core.windows.net).
locals {
  dns_zone_names = {
    blob       = "privatelink.blob.core.windows.net"
    cosmos     = "privatelink.documents.azure.com"
    search     = "privatelink.search.windows.net"
    vault      = "privatelink.vaultcore.azure.net"
    acr        = "privatelink.azurecr.io"
    openai     = "privatelink.openai.azure.com"
    cognitive  = "privatelink.cognitiveservices.azure.com"
    aiservices = "privatelink.services.ai.azure.com"
  }
}

resource "azurerm_private_dns_zone" "zones" {
  for_each            = local.dns_zone_names
  name                = each.value
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "links" {
  for_each              = local.dns_zone_names
  name                  = "link-${local.names.vnet}"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.zones[each.key].name
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false
  tags                  = var.tags
}
