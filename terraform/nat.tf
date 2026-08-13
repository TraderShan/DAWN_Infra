# =====================================================================================
#  Dawn - Terraform - NAT gateway (optional outbound internet egress)
# -------------------------------------------------------------------------------------
#  Outbound-only SNAT for the jumpbox (snet-mgmt) and container apps (snet-aca). A Standard
#  public IP fronts the NAT gateway; there is NO inbound exposure to the subnets. Gated on
#  var.deploy_nat_gateway. This is a deliberate deviation from strict "no public egress".
# =====================================================================================

resource "azurerm_public_ip" "nat" {
  count               = var.deploy_nat_gateway ? 1 : 0
  name                = "pip-nat-${local.names.vnet}"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  sku                 = "Standard"
  allocation_method   = "Static"
  tags                = var.tags
}

resource "azurerm_nat_gateway" "this" {
  count                   = var.deploy_nat_gateway ? 1 : 0
  name                    = "nat-${local.names.vnet}"
  resource_group_name     = azurerm_resource_group.this.name
  location                = var.location
  sku_name                = "Standard"
  idle_timeout_in_minutes = 4
  tags                    = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "this" {
  count                = var.deploy_nat_gateway ? 1 : 0
  nat_gateway_id       = azurerm_nat_gateway.this[0].id
  public_ip_address_id = azurerm_public_ip.nat[0].id
}

# Associate the NAT gateway with the jumpbox + ACA subnets.
resource "azurerm_subnet_nat_gateway_association" "mgmt" {
  count          = var.deploy_nat_gateway ? 1 : 0
  subnet_id      = azurerm_subnet.mgmt.id
  nat_gateway_id = azurerm_nat_gateway.this[0].id
}

resource "azurerm_subnet_nat_gateway_association" "aca" {
  count          = var.deploy_nat_gateway ? 1 : 0
  subnet_id      = azurerm_subnet.aca.id
  nat_gateway_id = azurerm_nat_gateway.this[0].id
}
