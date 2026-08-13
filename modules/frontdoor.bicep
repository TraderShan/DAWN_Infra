// =====================================================================================
//  Dawn - Azure Front Door (Premium) + WAF  ->  internal ACA "ui" app via Private Link
// -------------------------------------------------------------------------------------
//  Puts a public, WAF-protected front on the otherwise-private Dawn UI without exposing
//  the container app to the internet directly:
//
//    Internet ─▶ Front Door edge ─▶ WAF (DRS + Bot Manager + rate-limit)
//             ─▶ Private Link (managedEnvironments) ─▶ internal ACA env ILB ─▶ ui app
//
//  The internal ILB path (jumpbox via the greenbay-* private DNS zone) is UNAFFECTED —
//  this adds an ingress path, it does not replace the existing one.
//
//  NOTE (manual step): the shared Private Link creates a PENDING private-endpoint
//  connection on the ACA managed environment. It must be APPROVED before traffic flows.
//  deploy.sh approves it automatically after the deployment; see FRONTDOOR-EASYAUTH.md.
// =====================================================================================

@description('Global resource — the profile/endpoint live at the edge, but tags + RG scope apply.')
param tags object

@description('Name prefix, e.g. dawn-poc.')
param namePrefix string

@description('Resource id of the internal ACA managed environment (Private Link target).')
param acaEnvironmentId string

@description('Region of the ACA environment — required for the shared Private Link resource.')
param privateLinkLocation string

@description('Internal FQDN of the origin app (the ui container app), e.g. dawn-poc-ui.<env-default-domain>.')
param originHostName string

@description('WAF mode. Prevention actively blocks; Detection only logs (use while tuning).')
@allowed([
  'Prevention'
  'Detection'
])
param wafMode string = 'Prevention'

@description('Requests per minute, per client IP, before the rate-limit rule blocks.')
param rateLimitThreshold int = 100

// Front Door + WAF are global; names are RG-unique. WAF policy names must be alphanumeric.
var profileName = 'afd-${namePrefix}'
var endpointName = 'ep-${namePrefix}'
var originGroupName = 'og-ui'
var originName = 'origin-ui'
var routeName = 'route-ui'
var securityPolicyName = 'sp-ui'
var wafPolicyName = replace('waf${namePrefix}', '-', '')

// ------------------------------- Front Door profile (Premium) ------------------------
resource profile 'Microsoft.Cdn/profiles@2024-02-01' = {
  name: profileName
  location: 'global'
  tags: tags
  sku: {
    name: 'Premium_AzureFrontDoor' // Premium is REQUIRED for Private Link origins + managed WAF.
  }
}

// ------------------------------- WAF policy ------------------------------------------
resource waf 'Microsoft.Network/FrontDoorWebApplicationFirewallPolicies@2024-02-01' = {
  name: wafPolicyName
  location: 'Global'
  tags: tags
  sku: {
    name: 'Premium_AzureFrontDoor'
  }
  properties: {
    policySettings: {
      enabledState: 'Enabled'
      mode: wafMode
      requestBodyCheck: 'Enabled'
    }
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'Microsoft_DefaultRuleSet'
          ruleSetVersion: '2.1'
          ruleSetAction: 'Block'
        }
        {
          ruleSetType: 'Microsoft_BotManagerRuleSet'
          ruleSetVersion: '1.1'
        }
      ]
    }
    customRules: {
      rules: [
        {
          name: 'RateLimitPerClientIp'
          priority: 100
          enabledState: 'Enabled'
          ruleType: 'RateLimitRule'
          rateLimitDurationInMinutes: 1
          rateLimitThreshold: rateLimitThreshold
          // Count every request (every URL contains "/") toward the per-client-IP limit.
          matchConditions: [
            {
              matchVariable: 'RequestUri'
              operator: 'Contains'
              negateCondition: false
              matchValue: [
                '/'
              ]
              transforms: [
                'Lowercase'
              ]
            }
          ]
          action: 'Block'
        }
      ]
    }
  }
}

// ------------------------------- Endpoint --------------------------------------------
resource endpoint 'Microsoft.Cdn/profiles/afdEndpoints@2024-02-01' = {
  parent: profile
  name: endpointName
  location: 'global'
  tags: tags
  properties: {
    enabledState: 'Enabled'
  }
}

// ------------------------------- Origin group + origin (Private Link) ----------------
resource originGroup 'Microsoft.Cdn/profiles/originGroups@2024-02-01' = {
  parent: profile
  name: originGroupName
  properties: {
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
      additionalLatencyInMilliseconds: 50
    }
    healthProbeSettings: {
      probePath: '/'
      probeRequestType: 'HEAD'
      probeProtocol: 'Https'
      probeIntervalInSeconds: 100
    }
  }
}

resource origin 'Microsoft.Cdn/profiles/originGroups/origins@2024-02-01' = {
  parent: originGroup
  name: originName
  properties: {
    hostName: originHostName
    originHostHeader: originHostName
    httpPort: 80
    httpsPort: 443
    priority: 1
    weight: 1000
    enabledState: 'Enabled'
    enforceCertificateNameCheck: true
    // Shared Private Link to the ACA environment. Creates a PENDING connection on the
    // env that must be approved (deploy.sh does this post-deploy).
    sharedPrivateLinkResource: {
      privateLink: {
        id: acaEnvironmentId
      }
      groupId: 'managedEnvironments'
      privateLinkLocation: privateLinkLocation
      requestMessage: 'Azure Front Door Private Link to Dawn ACA (ui)'
    }
  }
}

// ------------------------------- Route ----------------------------------------------
resource route 'Microsoft.Cdn/profiles/afdEndpoints/routes@2024-02-01' = {
  parent: endpoint
  name: routeName
  properties: {
    originGroup: {
      id: originGroup.id
    }
    supportedProtocols: [
      'Http'
      'Https'
    ]
    patternsToMatch: [
      '/*'
    ]
    forwardingProtocol: 'HttpsOnly'
    linkToDefaultDomain: 'Enabled'
    httpsRedirect: 'Enabled' // force http -> https at the edge
    enabledState: 'Enabled'
  }
  dependsOn: [
    origin
  ]
}

// ------------------------------- Security policy (WAF <-> endpoint) ------------------
resource securityPolicy 'Microsoft.Cdn/profiles/securityPolicies@2024-02-01' = {
  parent: profile
  name: securityPolicyName
  properties: {
    parameters: {
      type: 'WebApplicationFirewall'
      wafPolicy: {
        id: waf.id
      }
      associations: [
        {
          domains: [
            {
              id: endpoint.id
            }
          ]
          patternsToMatch: [
            '/*'
          ]
        }
      ]
    }
  }
}

// ------------------------------- Outputs ---------------------------------------------
@description('Public hostname of the Front Door endpoint (https://<this>).')
output endpointHostName string = endpoint.properties.hostName

@description('Front Door profile name (for the private-endpoint-connection approval step).')
output profileName string = profile.name

@description('WAF policy name.')
output wafPolicyName string = waf.name
