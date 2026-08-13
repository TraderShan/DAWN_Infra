# Gap closure — from the original scaffold to `dawn-infra`

This maps every gap and difference from the gap analysis (Infrastructure doc vs the
original generic scaffold) to how it's resolved here. Items marked *platform/runtime* are
Foundry features that live in configuration/SDK rather than a resource template — noted so
nothing is silently dropped.

## Gaps closed

| # | Gap (from analysis) | Resolution in `dawn-infra` |
|---|---------------------|----------------------------|
| 1 | Only one placeholder ACA app | `containerApps` list deploys the FastAPI **UI** + 4 stubs (**CRM, Products, Core, Knowledge**) + **Toolbox**, via the reusable `containerapp` module |
| 2 | No overnight scheduled batch | `containerjob` module + `overnight-batch` job on a cron schedule (`0 9 * * *` UTC ≈ 5am ET) |
| 3 | No Toolbox (MCP gateway) | `toolbox` container app on the internal ACA env |
| 4 | No custom MCP servers | The four stub apps are the MCP source-system servers (hosted on ACA, on the VNet) |
| 5 | No Foundry IQ knowledge base | AI Search is provisioned as the knowledge plane and wired to the project via the `aisearch-knowledge` connection; the knowledge base itself is created in Foundry (SDK/portal) over this Search resource — see ARCHITECTURE.md |
| 6 | Tool traffic not on the VNet | Internal ACA env + Foundry agent **network injection** into `snet-agent` keep MCP/tool traffic on the VNet (BYO-agent-tools posture) |
| 7 | No secure access path | **Azure Bastion (Standard)** + a **Windows jumpbox** on `snet-mgmt` (Microsoft Entra login), reached over Bastion; VPN/ExpressRoute are alternatives; no *direct* public ingress to workloads (the optional Front Door + WAF edge — see the additions section below — is the one exception, and only to the ui app) |
| 8 | No CI/CD | GitHub Actions: `build-and-push-apps.yml` (images via `az acr build`) and `deploy-infrastructure.yml` (bicep or terraform) |
| 9 | Fabric not private | Fabric F4 retained; OneLake is its storage. *Fabric-data-agent VNet support is a platform feature configured in Fabric — capacity itself has no private endpoint* |
| 10 | Capability-host-before-RBAC ordering | **Fixed.** Capability host is now its own module (`foundry-capabilityhost`) deployed **after** the `rbac` module (`dependsOn: rbac`), so role assignments propagate first. The project identity also holds **Cosmos DB Operator** so the capability host can provision its agent thread-store containers |
| 11 | No Cosmos app data model | Cosmos now provisions the `dawn` database + containers: `accounts`, `opportunities`, `calls`, `signals`, `artifacts`, `conversations` |
| 12 | Conversation-state store | The `conversations` container covers app-managed memory (the BYO fallback if Foundry-managed memory isn't used) |

## Differences reconciled

| Aspect | Was | Now |
|--------|-----|-----|
| VNet address space | `10.20.0.0/16` | `192.168.0.0/16` (agent `…0.0/24`, PE `…1.0/24`) — matches the doc |
| Public ingress | ACA + Web App public | Internal ACA env, no *direct* public ingress; Bastion for access. **Optional** Front Door (Premium) + WAF edge to the **ui** app over Private Link when `deployFrontDoor = true` (see `FRONTDOOR-EASYAUTH.md`) |
| Compute model | Web App + one ACA app | ACA-hosted UI + stubs + toolbox; Web App optional/off |
| Capability host | created with the account | separate module, after RBAC |

> **ACA ingress model (confirmed in deployment):** apps run with `ingress.external = true` on
> the **internal** environment. On an internal env that means *reachable from the VNet* via the
> internal load balancer (`192.168.2.x`) — **not** internet-facing. `external = false` restricts
> an app to intra-environment (app-to-app) traffic only, which is why VNet clients like the
> jumpbox initially couldn't reach the apps (the `.internal.` FQDN). See NETWORKING.md.

## Added after the gap analysis (not in the original scaffold or the doc gaps)

These are net-new capabilities layered on after the gap analysis — listed here so the delta from
the original scaffold stays complete. Both are implemented in **Bicep and Terraform**.

| Addition | What it does |
|----------|--------------|
| **Azure Front Door (Premium) + WAF** (`deployFrontDoor`, **on** in params) | A public, WAF-protected edge (DRS 2.1 + Bot Manager 1.1 + per-IP rate-limit) in front of **only** the `ui` app, reaching it over **Private Link** to the internal ACA environment (`groupId: managedEnvironments`). The container app keeps **no public IP**; the internal Bastion/ILB path is unchanged. |
| **EasyAuth (Microsoft Entra ID)** (`enableEasyAuth`, **off** — Phase 2) | An Entra sign-in gate on the `ui` app, enforced at ingress on every path (Front Door *and* internal). Two-phase because its redirect URI needs the Front Door host, which only exists post-deploy. |

Full enablement + back-out runbook: [`FRONTDOOR-EASYAUTH.md`](FRONTDOOR-EASYAUTH.md).

## Platform / runtime items (not template-provisioned, documented instead)

- **Entra Agent ID** per-agent identities — the project has a managed identity; per-agent
  IDs are assigned by the hosted-agent runtime.
- **Foundry IQ** query planning / agentic retrieval (extractive mode), **Toolbox**
  curation, and **managed memory** are configured in Foundry (SDK/portal) over the
  resources provisioned here.
- **Continuous evaluation → Azure Monitor** is a Foundry setting; App Insights + Log
  Analytics are provisioned to receive it.
- **Outbound egress** uses a **NAT gateway** (outbound-only SNAT) on the management + ACA
  subnets — **deployed**, so the jumpbox and container apps reach the internet with no
  inbound exposure. *Strict* no-public-egress (FQDN allow-list) would instead use Azure
  Firewall + UDRs — not taken, to keep the POC simple (see NETWORKING.md / OPERATIONS.md).
- **Microsoft Defender for Cloud** plans (Servers, Storage, Key Vault, Cosmos, Containers,
  Resource Manager, AI Services) are provided as an **optional, subscription-scoped** add-on
  in `security/` — **not deployed by default**; see `security/README.md`.

## AI Search role note

The doc calls for **Search Index Data Reader** (read) or **Data Contributor** (write). The
RBAC module grants the project **Search Index Data Contributor** + **Search Service
Contributor** because the index/load jobs write to indexes. Narrow the project to
*Data Reader* if it only reads at runtime and a separate identity owns indexing.
