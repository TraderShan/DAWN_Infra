// Reusable Azure Container App (internal ingress). Used for the FastAPI UI, the four
// stubbed source systems (CRM, Products, Core, Knowledge), and the Toolbox MCP gateway.
// Every app pulls from ACR with the shared user-assigned identity and gets the App
// Insights connection string injected.

param location string
param tags object
param name string
param environmentId string
param uamiId string
param acrLoginServer string
param image string
param appInsightsConnectionString string

@description('Container listen port.')
param targetPort int = 8000

@description('Enable internal ingress for this app (UI/stubs/toolbox = true; pure workers = false).')
param ingressEnabled bool = true

@description('Extra environment variables (array of { name, value }).')
param extraEnv array = []

@description('CPU cores (e.g. 0.5) and memory (e.g. 1Gi).')
param cpu string = '0.5'
param memory string = '1Gi'
param minReplicas int = 1
param maxReplicas int = 3

// --- EasyAuth (ACA built-in authentication, Microsoft Entra ID) ---
@description('Enable EasyAuth (Entra ID) in front of this app. Typically only the ui app.')
param enableEasyAuth bool = false

@description('Entra app registration (client) ID for EasyAuth.')
param easyAuthClientId string = ''

@description('Entra tenant ID the app registration lives in (single-tenant sign-in).')
param easyAuthTenantId string = ''

@description('Entra app registration client secret. Supply securely (never hardcode).')
@secure()
param easyAuthClientSecret string = ''

@description('What to do with unauthenticated callers: redirect a browser to the Entra login, or return 401 (better for pure APIs).')
@allowed([
  'RedirectToLoginPage'
  'Return401'
])
param easyAuthUnauthenticatedAction string = 'RedirectToLoginPage'

// EasyAuth needs the client secret stored as a container-app secret it can reference.
var authSecretName = 'aad-client-secret'
var easyAuthSecrets = enableEasyAuth
  ? [
      {
        name: authSecretName
        value: easyAuthClientSecret
      }
    ]
  : []

var baseEnv = [
  {
    name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
    value: appInsightsConnectionString
  }
]

resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uamiId}': {}
    }
  }
  properties: {
    managedEnvironmentId: environmentId
    configuration: {
      activeRevisionsMode: 'Single'
      secrets: easyAuthSecrets
      ingress: ingressEnabled ? {
        // external: true on an INTERNAL environment = reachable from the VNet via the
        // environment's internal load balancer (still private, NOT internet-facing).
        // external: false would make the app reachable only by other apps IN the env.
        external: true
        targetPort: targetPort
        transport: 'auto'
      } : null
      registries: [
        {
          server: acrLoginServer
          identity: uamiId
        }
      ]
    }
    template: {
      containers: [
        {
          name: name
          image: image
          resources: {
            cpu: json(cpu)
            memory: memory
          }
          env: concat(baseEnv, extraEnv)
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
      }
    }
  }
}

// EasyAuth / Entra ID sign-in in front of the app. Single-tenant: only identities in
// easyAuthTenantId can sign in. Enforced at ingress on EVERY path (Front Door AND the
// internal ILB), so a token-less curl from the jumpbox will get 401/redirect once on.
resource authConfig 'Microsoft.App/containerApps/authConfigs@2024-03-01' = if (enableEasyAuth) {
  parent: app
  name: 'current'
  properties: {
    platform: {
      enabled: true
    }
    globalValidation: {
      unauthenticatedClientAction: easyAuthUnauthenticatedAction
      redirectToProvider: 'azureactivedirectory'
    }
    identityProviders: {
      azureActiveDirectory: {
        enabled: true
        registration: {
          openIdIssuer: 'https://login.microsoftonline.com/${easyAuthTenantId}/v2.0'
          clientId: easyAuthClientId
          clientSecretSettingName: authSecretName
        }
        validation: {
          // Accept both the bare client id (audience of the id_token from the interactive
          // login flow) and the api:// form (audience of access tokens issued to the app).
          allowedAudiences: [
            easyAuthClientId
            'api://${easyAuthClientId}'
          ]
        }
      }
    }
    login: {
      preserveUrlFragmentsForLogins: false
      tokenStore: {
        enabled: false // no token-store storage wired for the POC; enable + back with blob later
      }
    }
  }
}

output id string = app.id
output name string = app.name
output fqdn string = ingressEnabled ? app.properties.configuration.ingress.fqdn : ''
