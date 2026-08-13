// Windows jumpbox VM - the management host external users reach through Azure Bastion.
// No public IP; a NIC-level NSG allows RDP (3389) ONLY from the Bastion subnet. From here
// you can reach the internal ACA apps, private endpoints, the Foundry portal, and validate
// private DNS resolution inside the VNet.
//
// Access path: user -> Azure Portal (Entra sign-in) -> Bastion -> this VM over TLS 443.

param location string
param tags object
param name string
param subnetId string

@description('CIDR of the AzureBastionSubnet - the only source allowed to RDP to the VM.')
param bastionSubnetPrefix string

@description('Local administrator username.')
param adminUsername string

@description('Local administrator password (supply securely; e.g. Key Vault getSecret in the .bicepparam).')
@secure()
param adminPassword string

param vmSize string = 'Standard_D2s_v5'

@description('Send VM guest/platform metrics to Log Analytics? (boot diagnostics use managed storage).')
param logAnalyticsId string = ''

@description('Add the AADLoginForWindows extension so users sign in with their Entra (MCAPS-tenant) identity.')
param enableEntraLogin bool = true

@description('Entra object ID granted "Virtual Machine Administrator Login" on this VM (your MCAPS-tenant identity). Empty = skip the role assignment.')
param entraLoginPrincipalId string = ''

resource nsg 'Microsoft.Network/networkSecurityGroups@2023-11-01' = {
  name: 'nsg-${name}'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'Allow-RDP-from-Bastion'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: bastionSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '3389'
        }
      }
      {
        name: 'Deny-All-Inbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2023-11-01' = {
  name: 'nic-${name}'
  location: location
  tags: tags
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig'
        properties: {
          subnet: {
            id: subnetId
          }
          privateIPAllocationMethod: 'Dynamic'
          // no publicIPAddress - reachable only via Bastion
        }
      }
    ]
    networkSecurityGroup: {
      id: nsg.id
    }
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned' // required by the AADLoginForWindows extension
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: 'dawn-jumpbox' // Windows computerName must be <= 15 chars
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        // Plain Datacenter (Gen2) — NOT 'azure-edition', which has strict attestation and
        // can show "…has been deactivated because you are not running on Azure…". Standard
        // Datacenter activates via Azure KMS with none of that behavior.
        sku: '2022-datacenter-g2'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        deleteOption: 'Delete' // OS disk is removed when the VM is deleted (no orphaned disks)
        // OS-disk storage type is intentionally NOT forced here: Azure won't allow changing
        // an existing VM's disk type on redeploy, which fails the run. Azure picks a default
        // on create; change the disk SKU on the disk resource itself if you need a specific tier.
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true // managed boot diagnostics
      }
    }
  }
}

// Entra ID (Azure AD) login extension. Users then RDP with their Entra identity — for this
// subscription that is the MCAPS-tenant account (…@MngEnvMCAP776009.onmicrosoft.com), not
// the corp @microsoft.com account.
resource aadLogin 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = if (enableEntraLogin) {
  parent: vm
  name: 'AADLoginForWindows'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.ActiveDirectory'
    type: 'AADLoginForWindows'
    typeHandlerVersion: '2.0'
    autoUpgradeMinorVersion: true
  }
}

// "Virtual Machine Administrator Login" — RDP with admin rights via Entra identity, scoped
// to this VM only.
var vmAdminLoginRoleId = '1c0163c0-47e6-4577-8991-ea5c82e286e4'
resource vmAdminLogin 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableEntraLogin && !empty(entraLoginPrincipalId)) {
  name: guid(vm.id, entraLoginPrincipalId, vmAdminLoginRoleId)
  scope: vm
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', vmAdminLoginRoleId)
    principalId: entraLoginPrincipalId
    principalType: 'User'
  }
}

output id string = vm.id
output name string = vm.name
output privateIp string = nic.properties.ipConfigurations[0].properties.privateIPAddress
