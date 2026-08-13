# Architecture — how the infrastructure maps to Dawn

This environment provisions the platform the five Dawn documents describe. It stops at the
infrastructure seam: it stands up and networks the resources and wires the Foundry agent
platform to its BYO stores. Application code, agent logic, the policy object, and synthetic
data are the build phase's job.

## The shape

```
   Internet ─▶ Front Door (Premium) + WAF ─▶ Private Link ─▶ ui app   (optional; deployFrontDoor=true)
                         ┌──────────────── Azure Bastion (secure access) ───────────────┐
                         │             no direct public ingress to workloads              │
   ┌─────────────────────┴───────────────────  VNet 192.168.0.0/16  ─────────────────────┴───┐
   │                                                                                          │
   │  snet-agent (192.168.0.0/24)         snet-aca (192.168.2.0/24)                           │
   │  ┌───────────────────────────┐       ┌──────────────────── internal ACA env ─────────┐  │
   │  │ Foundry hosted agents     │       │  UI (FastAPI)   stub-crm  stub-products         │  │
   │  │ (MAF: overnight + AskDawn)│       │  stub-core      stub-knowledge   toolbox        │  │
   │  └────────────┬──────────────┘       │  jobs: overnight-batch (5am), seed/load/index   │  │
   │               │                       └───────────────┬────────────────────────────────┘  │
   │               │ MCP tools + retrieval (on-VNet)        │                                   │
   │  snet-pe (192.168.1.0/24)  ── private endpoints ──┐    │                                   │
   │   Foundry · Cosmos · AI Search · Storage · KV · ACR    │                                   │
   └────────────────────────────────────────────────────────┴───────────────────────────────┘
        Cosmos = serve path   OneLake/Fabric = analytical depth   AI Search = knowledge
```

> **Optional public edge (both engines).** With `deployFrontDoor = true` (the current param
> default), Azure **Front Door (Premium) + WAF** fronts *only* the **ui** app over **Private Link**
> to the internal ACA environment — the container app keeps no public IP. An optional **EasyAuth**
> (Entra ID) sign-in gate on the ui app can be turned on in Phase 2. Bastion remains the access path
> for the rest of the workloads. Details in `FRONTDOOR-EASYAUTH.md`.

## Component → Dawn role

| Resource | Dawn role (from the docs) |
|----------|---------------------------|
| **Foundry account + project** | The agent brain. Hosts the MAF agents (overnight signal-detection/ranking/brief pipeline + live Ask Dawn) on the managed, VNet-isolated runtime. |
| **Capability host** | Binds the project to its BYO stores: Cosmos (thread/state), Storage (files), AI Search (vectors). Deployed after RBAC. |
| **Cosmos DB** | Operational serve path. Read models the surfaces render, the precomputed **brief** + **ranking** artifacts (dated + versioned), signals with `basis`/`basisRef`, the three write targets, and (optionally) conversation state. |
| **AI Search** | Knowledge plane — the synthetic SOP/playbook/product corpus, retrieved by the agent through Foundry IQ in **extractive** mode over one MCP surface. |
| **Storage** | Foundry BYO at-rest store; also the landing spot for synthetic content that gets indexed into Search and loaded into OneLake. |
| **Fabric (F4) + OneLake** | Analytical depth the overnight agent reasons over (18 months of history across 25 accounts) and the institutional book-level reporting view. |
| **ACA env + apps** | The FastAPI UI, the four stubbed source systems (CRM/Products/Core/Knowledge, each FastAPI + SQLite), and the Toolbox MCP gateway — all internal. |
| **ACA jobs** | The overnight batch (scheduled ~5am) that writes artifacts to Cosmos, plus manual seed/load/index data jobs. |
| **ACR** | Private registry for the app/stub/agent images. |
| **Key Vault** | Residual secrets (keyless-first; RBAC mode). |
| **App Insights + Log Analytics** | Observability; receives Foundry agent tracing + continuous evaluation. |
| **Bastion** | The secure way in for the workloads; the only public entry is the optional Front Door + WAF edge to the ui app. |
| **Front Door (Premium) + WAF** *(optional)* | Public, WAF-protected edge (DRS 2.1 + Bot Manager 1.1 + per-IP rate-limit) to the **ui** app via Private Link — the only internet-facing path, and only when `deployFrontDoor = true`. |
| **EasyAuth (Entra ID)** *(optional)* | Entra sign-in gate on the ui app, enforced at ingress on every path; two-phase enablement (`enableEasyAuth`, off by default). |
| **Managed identity + RBAC** | Keyless service-to-service access; the project identity and the shared UAMI get data-plane roles. |

## Data flow (from the Data/Application docs)

1. **Stubs** hold synthetic system-of-record data → feed **OneLake** (analytical depth) and
   are indexed into **AI Search** (knowledge).
2. **Overnight** the agent reasons over OneLake depth, detects signals (with basis),
   ranks opportunities (with rationale), composes the brief → writes artifacts to **Cosmos**.
3. **Runtime** the UI reads Cosmos artifacts + read models instantly — it never triggers
   agent generation on load.
4. **Ask Dawn** is the only live call: retrieves from AI Search via Foundry IQ and reads
   sources via Toolbox, both through one MCP surface, and streams an answer.
5. **Fabric** draws on OneLake for the leadership reporting view (outside Nora's 7 surfaces).

## What the template does *not* do

Application/agent code, the policy object, MAF agent definitions, Foundry IQ knowledge-base
configuration, Toolbox tool curation, managed-memory vs BYO-memory selection, and synthetic
data generation are all build-phase work. The infrastructure exposes the resources, private
network, identities, and connections those pieces plug into.
