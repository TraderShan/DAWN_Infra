// Internal Azure Container Apps environment (no public ingress).
// VNet-integrated on the ACA subnet; all app ingress is internal-only, reachable from
// inside the VNet (via Bastion/VPN/ExpressRoute). This keeps tool traffic on the VNet.

param location string
param tags object
param name string
param acaSubnetId string
param logAnalyticsId string
param logAnalyticsName string

resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logAnalyticsName
}

resource acaEnv 'Microsoft.App/managedEnvironments@2024-10-02-preview' = {
  name: name
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: law.properties.customerId
        sharedKey: law.listKeys().primarySharedKey
      }
    }
    vnetConfiguration: {
      infrastructureSubnetId: acaSubnetId
      internal: true // no public ingress - private environment
    }
    // Internal environments have no public endpoint to begin with, so this is the only
    // supported value AND the default — setting it explicitly is a no-op for in-VNet
    // callers (the jumpbox still reaches apps over the internal ILB), and it is REQUIRED
    // to attach the Azure Front Door shared Private Link.
    publicNetworkAccess: 'Disabled'
    zoneRedundant: false
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
  }
}

resource diag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-to-law'
  scope: acaEnv
  properties: {
    workspaceId: logAnalyticsId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
  }
}

output id string = acaEnv.id
output name string = acaEnv.name
output defaultDomain string = acaEnv.properties.defaultDomain
output staticIp string = acaEnv.properties.staticIp
