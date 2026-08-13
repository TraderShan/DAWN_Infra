# Dawn — Private Infrastructure (POC)

Infrastructure-as-code for the **Dawn** solution: a private, single-region, Foundry-centered
environment for the July-21 leadership demo. Built to the five architecture documents
(PRD, Application, Agent, Data, Infrastructure) and re-worked from the original generic
scaffold to close the gaps found in the gap analysis.

Two engines are provided — **Bicep** and **Terraform** — and one `deploy.sh` that lets you
pick either. Everything is keyless (managed identity + RBAC), private-endpoint only on the
data tier, and has **no public ingress** (access is via Azure Bastion).

> **Not validated in a live tenant.** These templates were authored offline. Run
> `az bicep build` / `terraform validate` and a what-if/plan before deploying. The Foundry
> agent pieces (project connections, capability host, network injection) use **preview**
> API shapes — see `OPERATIONS.md`.

---

## What it deploys

| Area | Resources |
|------|-----------|
| **Network** | VNet `192.168.0.0/16`; subnets for agent, private endpoints, ACA, Bastion, App Service; 8 private DNS zones |
| **Secure access** | Azure Bastion (no public ingress to workloads) |
| **Identity** | 1 user-assigned managed identity + RBAC everywhere |
| **AI** | Azure AI Foundry (AIServices) account + project, BYO connections (Cosmos/Storage/Search), capability host, optional model deployments |
| **Data** | Cosmos DB (NoSQL serverless) with Dawn containers; Azure AI Search; Storage; Microsoft Fabric (F4, OneLake) |
| **Compute** | Internal ACA environment; container apps for the FastAPI **UI**, 4 stubs (**CRM, Products, Core, Knowledge**), and **Toolbox**; ACA **jobs** for the 5am overnight batch + seed/load/index |
| **Platform** | Premium ACR (private), Key Vault (private), Log Analytics + App Insights |
| **Edge (optional)** | Azure **Front Door (Premium) + WAF** in front of the **ui** app via Private Link; **EasyAuth** (Entra ID sign-in) on the ui app — see [`FRONTDOOR-EASYAUTH.md`](FRONTDOOR-EASYAUTH.md) |
| **CI/CD** | GitHub Actions: build/push images (`az acr build`) + deploy infra (bicep or terraform) |
| **Optional** | Web App / App Service — carried forward but **off by default** (Dawn serves the UI on ACA) |

---

## File layout

```
dawn-infra/
├── main.bicep                 # Bicep orchestrator
├── main.bicepparam            # Bicep parameters (edit the TODOs)
├── deploy.sh                  # deploy with --engine bicep|terraform
├── README.md · ARCHITECTURE.md · ARCHITECTURE-DIAGRAM.md · NETWORKING.md · GAP-CLOSURE.md · OPERATIONS.md · STATUS.md
├── modules/                   # Bicep modules
│   ├── identity · network · bastion · observability
│   ├── storage · cosmos · search · registry · keyvault
│   ├── foundry · foundry-capabilityhost · rbac
│   ├── containerapps-env · containerapp · containerjob · webapp
│   └── fabric
├── terraform/                 # Full-parity Terraform (consolidated topic files)
│   ├── versions · providers · variables · locals · outputs · terraform.tfvars.example
│   └── network · bastion · identity · observability · datastores
│       · registry · keyvault · foundry · compute · rbac · fabric
├── security/                  # OPTIONAL, subscription-scoped — Microsoft Defender for Cloud
│   ├── defender.bicep · defender.tf · README.md
└── .github/workflows/
    ├── build-and-push-apps.yml
    └── deploy-infrastructure.yml
```

> **Optional add-on:** `security/` enables Microsoft Defender for Cloud plans. It's
> **subscription-scoped** (affects the whole subscription, not just this RG) and deployed
> separately — see `security/README.md`.

> **Diagram:** `ARCHITECTURE-DIAGRAM.md` has Mermaid views of the full deployed topology,
> RBAC linkages, and Foundry/Cosmos data model (renders in GitHub/VS Code). `STATUS.md` is
> the point-in-time deployment snapshot.

`main.bicep` references modules by relative path and the Terraform lives in `terraform/`,
so keep the directory intact when you copy it into a repo.

---

## Prerequisites

- Azure CLI (`az`) and, for the Terraform path, `terraform >= 1.5`.
- Rights to create resources + role assignments in the target subscription (RBAC writes
  require Owner or User Access Administrator on the resource group).
- A region that supports **Foundry hosted agents** (default `swedencentral`). VNet and Foundry
  must be co-located.
- Create the Foundry project **fresh** (a project created after 2026-06-25 gets the
  private-ACR behavior this template assumes).

## Fill in before deploying

- `fabricAdminMembers` / `fabric_admin_members` — at least one capacity admin.
- `testerPrincipalId` / `tester_principal_id` *(optional)* — your Entra object ID for
  hands-on data access: `az ad signed-in-user show --query id -o tsv`.
- Model deployment is **on** — chat `gpt-5.4` + embedding `text-embedding-3-large`, each at
  100K TPM (`capacity = 100`). Edit the `*ModelName` / `*Capacity` params to change.
- Container images default to a placeholder — swap in your ACR images after the first
  `build-and-push-apps` run.

---

## Deploy

```bash
# Bicep
bash deploy.sh --engine bicep --what-if-only     # preview
bash deploy.sh --engine bicep                    # deploy

# Terraform
bash deploy.sh --engine terraform --plan-only    # preview
bash deploy.sh --engine terraform                # apply
```

`deploy.sh` checks sign-in, registers providers, previews, asks for confirmation, then
deploys and prints outputs. Override defaults with env vars
(`RESOURCE_GROUP`, `LOCATION`, `SUBSCRIPTION`).

See **OPERATIONS.md** for the private-networking failure modes to expect, the preflight
step, and the teardown order — private Foundry can deploy green and still fail the first
tool call, so budget for it.
