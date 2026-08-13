// Spoke VNet + subnets + Private DNS zones for the Dawn private environment.
// Address space matches the Infrastructure Architecture doc: 192.168.0.0/16, with the
// agent subnet at 192.168.0.0/24 and the private-endpoint subnet at 192.168.1.0/24.

param location string
param tags object
param vnetName string

param vnetAddressPrefix string = '192.168.0.0/16'
param agentSubnetPrefix string = '192.168.0.0/24'   // delegated to Microsoft.App/environments (Foundry hosted agents)
param peSubnetPrefix string = '192.168.1.0/24'      // private endpoints for Foundry, Cosmos, Search, Storage, KV, ACR
param acaSubnetPrefix string = '192.168.2.0/24'     // delegated to Microsoft.App/environments (ACA workloads)
param bastionSubnetPrefix string = '192.168.3.0/26' // AzureBastionSubnet (name is fixed, /26 minimum)
param appSvcSubnetPrefix string = '192.168.4.0/24'  // delegated to Microsoft.Web/serverFarms (optional Web App)
param mgmtSubnetPrefix string = '192.168.5.0/24'    // undelegated - hosts the optional jumpbox VM

@description('Deploy a NAT gateway for outbound internet on snet-mgmt (jumpbox) + snet-aca (container apps).')
param deployNatGateway bool = false

// Outbound-only SNAT: public IP fronts the NAT gateway; no inbound exposure to the subnets.
resource natPip 'Microsoft.Network/publicIPAddresses@2023-11-01' = if (deployNatGateway) {
  name: 'pip-nat-${vnetName}'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource natGateway 'Microsoft.Network/natGateways@2023-11-01' = if (deployNatGateway) {
  name: 'nat-${vnetName}'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    idleTimeoutInMinutes: 4
    publicIpAddresses: [
      {
        id: natPip.id
      }
    ]
  }
}

// Resource-ID string (not a symbolic reference to the conditional resource) — avoids the
// "conditional resource referenced from a non-conditional resource" issue in the subnets.
// The VNet takes an explicit dependency on the NAT gateway below.
var natGatewayId = deployNatGateway ? resourceId('Microsoft.Network/natGateways', 'nat-${vnetName}') : ''

var dnsZoneNames = {
  blob: 'privatelink.blob.${environment().suffixes.storage}'
  cosmos: 'privatelink.documents.azure.com'
  search: 'privatelink.search.windows.net'
  vault: 'privatelink.vaultcore.azure.net'
  acr: 'privatelink.azurecr.io'
  openai: 'privatelink.openai.azure.com'
  cognitive: 'privatelink.cognitiveservices.azure.com'
  aiservices: 'privatelink.services.ai.azure.com'
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: vnetName
  location: location
  tags: tags
  // Explicit dependency: the NAT gateway must exist before the subnets reference its ID.
  // (dependsOn on a conditional resource is skipped by ARM when it isn't deployed.)
  dependsOn: [
    natGateway
  ]
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: 'snet-agent'
        properties: {
          addressPrefix: agentSubnetPrefix
          delegations: [
            {
              name: 'agent-delegation'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }
      }
      {
        name: 'snet-pe'
        properties: {
          addressPrefix: peSubnetPrefix
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
      {
        name: 'snet-aca'
        properties: {
          addressPrefix: acaSubnetPrefix
          natGateway: !empty(natGatewayId) ? { id: natGatewayId } : null
          delegations: [
            {
              name: 'aca-delegation'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }
      }
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: bastionSubnetPrefix
        }
      }
      {
        name: 'snet-appsvc'
        properties: {
          addressPrefix: appSvcSubnetPrefix
          delegations: [
            {
              name: 'appsvc-delegation'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
        }
      }
      {
        // Undelegated management subnet for the optional jumpbox VM (Bastion target).
        name: 'snet-mgmt'
        properties: {
          addressPrefix: mgmtSubnetPrefix
          natGateway: !empty(natGatewayId) ? { id: natGatewayId } : null
        }
      }
    ]
  }
}

resource dnsZones 'Microsoft.Network/privateDnsZones@2020-06-01' = [for z in items(dnsZoneNames): {
  name: z.value
  location: 'global'
  tags: tags
}]

resource dnsLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [for z in items(dnsZoneNames): {
  name: '${z.value}/link-${vnetName}'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
  dependsOn: [
    dnsZones
  ]
}]

output vnetId string = vnet.id
output agentSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, 'snet-agent')
output peSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, 'snet-pe')
output acaSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, 'snet-aca')
output bastionSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, 'AzureBastionSubnet')
output appSvcSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, 'snet-appsvc')
output mgmtSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, 'snet-mgmt')

output dnsZoneIds object = {
  blob: resourceId('Microsoft.Network/privateDnsZones', dnsZoneNames.blob)
  cosmos: resourceId('Microsoft.Network/privateDnsZones', dnsZoneNames.cosmos)
  search: resourceId('Microsoft.Network/privateDnsZones', dnsZoneNames.search)
  vault: resourceId('Microsoft.Network/privateDnsZones', dnsZoneNames.vault)
  acr: resourceId('Microsoft.Network/privateDnsZones', dnsZoneNames.acr)
  openai: resourceId('Microsoft.Network/privateDnsZones', dnsZoneNames.openai)
  cognitive: resourceId('Microsoft.Network/privateDnsZones', dnsZoneNames.cognitive)
  aiservices: resourceId('Microsoft.Network/privateDnsZones', dnsZoneNames.aiservices)
}
