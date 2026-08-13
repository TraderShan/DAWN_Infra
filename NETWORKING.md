# Networking — IP plan & private DNS

The address space matches the Infrastructure Architecture document
(`192.168.0.0/16`, agent subnet `192.168.0.0/24`, private-endpoint subnet
`192.168.1.0/24`). Everything else fits around those two fixed values.

## Subnet plan

| Subnet | CIDR | Delegation / purpose |
|--------|------|----------------------|
| `snet-agent` | `192.168.0.0/24` | Delegated to `Microsoft.App/environments`. Foundry hosted-agent network injection. Dedicated to this Foundry resource — cannot be shared. |
| `snet-pe` | `192.168.1.0/24` | Private endpoints for Foundry, Cosmos, AI Search, Storage, Key Vault, ACR. PE network policies disabled. |
| `snet-aca` | `192.168.2.0/24` | Delegated to `Microsoft.App/environments`. Internal ACA environment (UI, stubs, Toolbox, jobs). |
| `AzureBastionSubnet` | `192.168.3.0/26` | Azure Bastion (fixed name, `/26` minimum). |
| `snet-appsvc` | `192.168.4.0/24` | Delegated to `Microsoft.Web/serverFarms`. Only used if the optional Web App is enabled. |
| `snet-mgmt` | `192.168.5.0/24` | Undelegated. Hosts the optional Windows jumpbox VM (Bastion target). Created always; VM only when `deployJumpbox = true`. |

**Jumpbox access path:** external user → Azure Portal (Entra sign-in) → **Bastion** → jumpbox VM in `snet-mgmt` (RDP over TLS 443). The VM has **no public IP**; a NIC-level NSG allows RDP (3389) only from the Bastion subnet. A VM can't live in the delegated subnets (`snet-agent`, `snet-aca`, `snet-appsvc`) or in `AzureBastionSubnet`, which is why `snet-mgmt` exists.

Adjust any prefix via parameters/variables. Keep `snet-agent` and `snet-pe` on the two
document-specified values unless you have a reason to move them.

## Ingress / egress posture

- **No public ingress.** The ACA environment is `internal: true`; every app uses
  internal-only ingress. Reach the UI and tools through **Azure Bastion** (VPN or
  ExpressRoute are drop-in alternatives).
- **Optional public edge for the UI (Front Door + WAF).** When `deployFrontDoor = true`,
  Azure Front Door (Premium) fronts *only* the **ui** app over **Private Link** to the ACA
  environment (`groupId: managedEnvironments`) — the container app still has no public IP.
  The path is `Internet → Front Door → WAF → Private Link → internal ILB → ui`. This is
  additive: the internal Bastion/ILB path is unchanged, and the WAF (DRS 2.1 + Bot Manager
  + per-IP rate limit) plus optional **EasyAuth** Entra sign-in gate the public surface.
  Setup, the required Private Link approval, and back-out are in
  [`FRONTDOOR-EASYAUTH.md`](FRONTDOOR-EASYAUTH.md).
- **Private data plane.** Storage, Cosmos, AI Search, Foundry, Key Vault, and ACR all have
  public network access **disabled** and are reached over private endpoints.
- **Egress (NAT gateway, optional).** Because Azure retired *default outbound access*
  (Sept 30, 2025), a private subnet has **no internet egress** unless you provide one. The
  optional **`deployNatGateway`** flag (`deploy_nat_gateway` in Terraform) adds a NAT
  gateway + Standard public IP and associates it with **`snet-mgmt`** (jumpbox) and
  **`snet-aca`** (container apps). This is **outbound-only SNAT — no inbound exposure**, so
  the "no public ingress" posture is preserved. It's a deliberate deviation from strict
  *no public egress*; leave the flag off to keep zero outbound. The data tier never needs
  it (private endpoints), and ACA image pulls use the platform path regardless — so the flag
  only matters for the jumpbox's own browsing and the app's outbound API calls (e.g. the
  external news/rate feed).
- For a *fully* controlled egress (allow-list specific FQDNs), replace the NAT gateway with
  an Azure Firewall + a route table (UDR) — heavier, left out to keep the POC simple.

## Private DNS zones (linked to the VNet)

| Zone | Serves |
|------|--------|
| `privatelink.blob.core.windows.net` | Storage (blob) |
| `privatelink.documents.azure.com` | Cosmos DB (Sql) |
| `privatelink.search.windows.net` | AI Search |
| `privatelink.vaultcore.azure.net` | Key Vault |
| `privatelink.azurecr.io` | Container Registry |
| `privatelink.openai.azure.com` | Foundry / AIServices |
| `privatelink.cognitiveservices.azure.com` | Foundry / AIServices |
| `privatelink.services.ai.azure.com` | Foundry / AIServices |

The Foundry account private endpoint registers across all three AI zones — all three are
required for full resolution. **Validate DNS resolution from inside the VNet** after
deploy; an approved private endpoint with an unlinked zone resolves to a public IP and the
call is rejected (a classic private-Foundry failure — see `OPERATIONS.md`).

## Container Apps: internal env, ingress, and DNS

- The ACA environment is **internal** (`internal_load_balancer_enabled = true`) with a
  private static IP — no public ingress.
- Each app uses **`external: true`** ingress. On an *internal* environment this means
  "reachable from the VNet via the internal load balancer" — **still private, not
  internet-facing**. (`external: false` would make an app reachable only by *other apps
  inside the environment*, which is why VNet clients like the jumpbox get a 404.) With
  `external: true` the app FQDN is `<app>.<envDefaultDomain>` (no `.internal.`).
- The template auto-creates a **Private DNS Zone** named the environment's `defaultDomain`
  (e.g. `greenbay-xxxx.<region>.azurecontainerapps.io`), a `*` A record → the env's static
  IP, and a VNet link (`modules/aca-private-dns.bicep` / the `aca_*` resources in
  `compute.tf`). Without it, app FQDNs don't resolve from inside the VNet.
- **Test from an in-VNet host** (jumpbox) using the exact FQDN from
  `az containerapp show … --query properties.configuration.ingress.fqdn` — don't hand-type it.

## Region

VNet and Foundry must be in the same region, and that region must support Foundry hosted
agents. Default `swedencentral`. The `192.168.x` space is a private (RFC 1918) range; confirm it
doesn't overlap any peered network or reserved range before you deploy.
