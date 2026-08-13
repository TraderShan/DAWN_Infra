// =====================================================================================
//  Microsoft Defender for Cloud - subscription-scoped plan enablement
// -------------------------------------------------------------------------------------
//  DELIBERATELY SEPARATE from the main RG-scoped template: Defender plans apply to the
//  WHOLE subscription (every resource of each type), not just the Dawn resource group.
//  Enabling these turns on threat protection - and billing - for ALL matching resources
//  in the subscription. See README.md for the cost / blast-radius notes and how to back out.
//
//  Deploy (subscription scope):
//    az deployment sub create --location swedencentral \
//      --template-file defender.bicep [-p securityContactEmail='you@microsoft.com']
// =====================================================================================

targetScope = 'subscription'

@description('Defender plans to enable at Standard tier. subPlan applies only to plans that support it (VirtualMachines, StorageAccounts).')
param plans array = [
  { name: 'VirtualMachines', subPlan: 'P2' }                   // Defender for Servers (jumpbox) - P1 is cheaper
  { name: 'StorageAccounts', subPlan: 'DefenderForStorageV2' } // Defender for Storage
  { name: 'KeyVaults', subPlan: '' }                           // Defender for Key Vault
  { name: 'CosmosDbs', subPlan: '' }                           // Defender for Cosmos DB
  { name: 'Containers', subPlan: '' }                          // Defender for Containers (ACR image scanning)
  { name: 'Arm', subPlan: '' }                                 // Defender for Resource Manager
  { name: 'AI', subPlan: '' }                                  // Defender for AI Services (Foundry / Azure OpenAI).
  //                                                              NOTE: newer plan - if it errors, remove this entry
  //                                                              and enable via: az security pricing create -n AI --tier Standard
]

@description('Optional email for Defender alert notifications. Leave empty to skip the security contact.')
param securityContactEmail string = ''

resource pricings 'Microsoft.Security/pricings@2024-01-01' = [for p in plans: {
  name: p.name
  properties: union(
    {
      pricingTier: 'Standard'
    },
    empty(p.subPlan) ? {} : {
      subPlan: p.subPlan
    }
  )
}]

resource contact 'Microsoft.Security/securityContacts@2023-12-01-preview' = if (!empty(securityContactEmail)) {
  name: 'default'
  properties: {
    emails: securityContactEmail
    notificationsByRole: {
      state: 'On'
      roles: [
        'Owner'
      ]
    }
    alertNotifications: {
      state: 'On'
      minimalSeverity: 'Medium'
    }
  }
}

output enabledPlans array = [for p in plans: p.name]
