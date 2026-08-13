// App Service plan + Linux container Web App (VNet-integrated, ACR pull via UAMI) + diagnostics.

param location string
param tags object
param planName string
param webAppName string
param appServicePlanSku string

param appSvcSubnetId string
param logAnalyticsId string
param uamiId string
param uamiClientId string
param appInsightsConnectionString string
param sampleContainerImage string
param computePublicIngress bool

resource appPlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: planName
  location: location
  tags: tags
  sku: {
    name: appServicePlanSku
  }
  kind: 'linux'
  properties: {
    reserved: true
  }
}

resource webApp 'Microsoft.Web/sites@2023-12-01' = {
  name: webAppName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uamiId}': {}
    }
  }
  properties: {
    serverFarmId: appPlan.id
    httpsOnly: true
    virtualNetworkSubnetId: appSvcSubnetId
    vnetRouteAllEnabled: true
    publicNetworkAccess: computePublicIngress ? 'Enabled' : 'Disabled'
    keyVaultReferenceIdentity: uamiId
    siteConfig: {
      linuxFxVersion: 'DOCKER|${sampleContainerImage}'
      acrUseManagedIdentityCreds: true
      acrUserManagedIdentityID: uamiClientId
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      appSettings: [
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsightsConnectionString
        }
        {
          name: 'WEBSITES_PORT'
          value: '80'
        }
      ]
    }
  }
}

resource diagSite 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-to-law'
  scope: webApp
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

resource diagPlan 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-to-law'
  scope: appPlan
  properties: {
    workspaceId: logAnalyticsId
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

output hostname string = webApp.properties.defaultHostName
