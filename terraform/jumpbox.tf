# =====================================================================================
#  Dawn - Terraform - Windows jumpbox (optional; count on var.deploy_jumpbox)
# -------------------------------------------------------------------------------------
#  Management VM external users reach through Azure Bastion. No public IP; a NIC-level NSG
#  allows RDP (3389) ONLY from the Bastion subnet. From here you reach the internal ACA
#  apps, private endpoints, the Foundry portal, and can validate private DNS in the VNet.
#  Access path: user -> Azure Portal (Entra) -> Bastion -> this VM over TLS 443.
# =====================================================================================

resource "azurerm_network_security_group" "jumpbox" {
  count               = var.deploy_jumpbox ? 1 : 0
  name                = "nsg-vm-jump-${local.name_prefix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags

  security_rule {
    name                       = "Allow-RDP-from-Bastion"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = var.bastion_subnet_prefix
    source_port_range          = "*"
    destination_address_prefix = "*"
    destination_port_range     = "3389"
  }

  security_rule {
    name                       = "Deny-All-Inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_address_prefix      = "*"
    source_port_range          = "*"
    destination_address_prefix = "*"
    destination_port_range     = "*"
  }
}

resource "azurerm_network_interface" "jumpbox" {
  count               = var.deploy_jumpbox ? 1 : 0
  name                = "nic-vm-jump-${local.name_prefix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags

  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = azurerm_subnet.mgmt.id
    private_ip_address_allocation = "Dynamic"
    # no public_ip_address_id - reachable only via Bastion
  }
}

resource "azurerm_network_interface_security_group_association" "jumpbox" {
  count                     = var.deploy_jumpbox ? 1 : 0
  network_interface_id      = azurerm_network_interface.jumpbox[0].id
  network_security_group_id = azurerm_network_security_group.jumpbox[0].id
}

resource "azurerm_windows_virtual_machine" "jumpbox" {
  count               = var.deploy_jumpbox ? 1 : 0
  name                = "vm-jump-${local.name_prefix}"
  computer_name       = "dawn-jumpbox" # Windows computerName must be <= 15 chars
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  size                = var.jumpbox_vm_size
  admin_username      = var.jumpbox_admin_username
  admin_password      = var.jumpbox_admin_password
  tags                = var.tags

  network_interface_ids = [azurerm_network_interface.jumpbox[0].id]

  identity {
    type = "SystemAssigned" # required by the AADLoginForWindows extension
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    # Plain Datacenter (Gen2), NOT 'azure-edition' — avoids the strict attestation that shows
    # "…deactivated because you are not running on Azure…". Changing this forces VM replacement.
    sku     = "2022-datacenter-g2"
    version = "latest"
  }
}

# Entra ID (Azure AD) login extension. Users then RDP with their Entra identity — for this
# subscription that is the MCAPS-tenant account (…@MngEnvMCAP776009.onmicrosoft.com).
resource "azurerm_virtual_machine_extension" "aad_login" {
  count                      = var.deploy_jumpbox && var.enable_entra_login ? 1 : 0
  name                       = "AADLoginForWindows"
  virtual_machine_id         = azurerm_windows_virtual_machine.jumpbox[0].id
  publisher                  = "Microsoft.Azure.ActiveDirectory"
  type                       = "AADLoginForWindows"
  type_handler_version       = "2.0"
  auto_upgrade_minor_version = true
}

# "Virtual Machine Administrator Login" — RDP with admin rights via Entra identity, scoped
# to this VM only.
resource "azurerm_role_assignment" "vm_admin_login" {
  count                = var.deploy_jumpbox && var.entra_login_principal_id != "" ? 1 : 0
  scope                = azurerm_windows_virtual_machine.jumpbox[0].id
  role_definition_name = "Virtual Machine Administrator Login"
  principal_id         = var.entra_login_principal_id
  principal_type       = "User"
}
