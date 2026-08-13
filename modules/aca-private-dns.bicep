// Private DNS Zone for the internal Container Apps environment.
// Internal ACA environments don't auto-create a DNS zone — without this, app FQDNs
// (<app>.<envDefaultDomain>) won't resolve from inside the VNet. This zone + wildcard
// record + VNet link make every app in the environment resolvable to the env's internal IP.
//
// Note: with apps set to external ingress (external: true) on an internal environment, the
// app FQDN is <app>.<defaultDomain> (no ".internal."), so a single-label "*" wildcard
// covers them all.

param zoneName string       // the environment's defaultDomain, e.g. greenbay-xxxx.<region>.azurecontainerapps.io
param staticIp string       // the environment's internal static IP
param vnetId string
param vnetName string
param tags object

resource zone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: zoneName
  location: 'global'
  tags: tags
}

resource wildcard 'Microsoft.Network/privateDnsZones/A@2020-06-01' = {
  parent: zone
  name: '*'
  properties: {
    ttl: 3600
    aRecords: [
      {
        ipv4Address: staticIp
      }
    ]
  }
}

resource link 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: zone
  name: 'link-${vnetName}'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

output zoneName string = zone.name
