// Azure Bastion - the secure access path into the private environment.
// The doc requires "no public ingress"; team/demo access comes through Bastion
// (VPN or ExpressRoute are alternatives). Bastion itself needs a public IP, but the
// workloads stay private - access is brokered through the Bastion host over TLS.

param location string
param tags object
param name string
param bastionSubnetId string
param logAnalyticsId string

@description('Bastion SKU. Basic is fine for a POC; Standard adds native client + IP-based connect.')
@allowed([
  'Basic'
  'Standard'
])
param sku string = 'Basic'

resource publicIp 'Microsoft.Network/publicIPAddresses@2023-11-01' = {
  name: 'pip-${name}'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource bastion 'Microsoft.Network/bastionHosts@2023-11-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: sku
  }
  properties: {
    // Native-client support (az network bastion rdp/tunnel). Requires Standard SKU.
    enableTunneling: sku == 'Standard'
    ipConfigurations: [
      {
        name: 'ipconfig'
        properties: {
          subnet: {
            id: bastionSubnetId
          }
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
  }
}

resource diag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-to-law'
  scope: bastion
  properties: {
    workspaceId: logAnalyticsId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

output id string = bastion.id
output name string = bastion.name
output publicIp string = publicIp.properties.ipAddress
