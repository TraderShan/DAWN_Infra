# Dawn Infrastructure — Deployment Status

> **Snapshot as of: Wednesday, July 8, 2026 — 10:42 AM ET (US Eastern).**
> This file is a point-in-time status. It reflects the environment **at that moment** and
> is not auto-updated — re-check against Azure before relying on it later.

- **Resource group:** `rg-dawn-fsi-poc`
- **Subscription:** `3a8f035c-5882-4df8-90f7-eb11a8bda066` (MCAPS)
- **Region:** Sweden Central
- **IaC:** `dawn-infra` — Bicep + Terraform at full parity (deployed via Bicep)
- **Posture:** private-by-design, keyless (managed identity + RBAC), no public ingress

---

## ✅ Deployed, live & validated

| Area | What's running | Verified |
|---|---|---|
| **Networking** | VNet `192.168.0.0/16` + 6 subnets; private DNS zones (data tier) + ACA env DNS zone | ✅ |
| **NAT gateway** | Outbound-only SNAT for jumpbox + ACA subnets | ✅ egress returns NAT public IP |
| **Identity / observability** | User-assigned managed identity, Log Analytics, App Insights | ✅ |
| **Data tier (private endpoints)** | Storage, Cosmos DB (`dawn` DB + containers), AI Search, ACR (Premium), Key Vault | ✅ |
| **AI platform** | Foundry account + project + capability host + 3 BYO connections | ✅ agent stack live |
| **Analytics** | Microsoft Fabric **F4** capacity | ✅ |
| **Compute** | Internal ACA environment, **6 container apps**, 4 ACA jobs | ✅ all 6 apps serve Hello World over VNet |
| **Access** | Azure Bastion (Standard) + Windows jumpbox (Entra login) | ✅ |

**End-to-end confidence checks passed (from jumpbox):**
- `curl https://ifconfig.me` → returned the NAT gateway's public IP (egress works)
- `curl -k https://<app>.greenbay-11dd3bec.swedencentral.azurecontainerapps.io/` → returned Hello World (app reachability works)

**Redeploy safety:** `agentStackDeployed = true` in `main.bicepparam` — re-runs skip the
locked Foundry connections + capability host. (Set to `false` only for a brand-new environment.)

---

## ⚪ Optional — in the template, OFF by default (not deployed)

| Item | Flag | Notes |
|---|---|---|
| Web App / App Service | `deployWebApp = false` | Dawn serves the UI on ACA |
| Front Door (Premium) + WAF on the ui app | `deployFrontDoor = true` in params (not yet applied as of this snapshot) | Public, WAF-protected entry via Private Link. `Microsoft.Cdn` register + Private Link approval handled by `deploy.sh`. See [`FRONTDOOR-EASYAUTH.md`](FRONTDOOR-EASYAUTH.md) |
| EasyAuth (Entra ID) on the ui app | `enableEasyAuth = false` | Two-phase: needs an Entra app registration against the Front Door host first. Runbook in [`FRONTDOOR-EASYAUTH.md`](FRONTDOOR-EASYAUTH.md) |

## 📦 Optional add-on — in repo, NOT run

- **Microsoft Defender for Cloud** — `security/` (subscription-scoped; deploy separately).
  Files present: `defender.bicep`, `defender.tf`, `README.md` (incl. back-out steps).

---

## 🚧 Remaining to enable / onboard (beyond infra — nothing blocking the platform)

1. **Foundry models — enabled in params, pending redeploy.** Chat `gpt-5.4` (`2025-03-05`) + embedding `text-embedding-3-large` are set to deploy at **100K TPM each** (`capacity = 100`). Each draws from its own 1M-TPM GlobalStandard pool in Sweden Central, so **no quota request is needed** — just **redeploy** to create the two model deployments. Ask Dawn stays a placeholder until that apply runs.
2. **Real app/agent images** — build UI/stubs/agents → push to ACR (`build-and-push-apps` workflow) → repoint each app's `image` and set `targetPort` to the app's real port (e.g. 8000).
3. **Foundry IQ knowledge base**, MAF agents, policy object, synthetic data — build-phase.
4. **CI/CD** — Entra OIDC app + GitHub repo secrets/variables (only needed to use the pipelines).
5. **Cost management** — Fabric F4, Premium ACR, Bastion Standard, NAT gateway (and Defender if enabled) bill continuously. **Pause Fabric when idle**; consider a dedicated cost/sizing pass.

---

## Container apps (current state)
`dawn-poc-ui`, `dawn-poc-stub-crm`, `dawn-poc-stub-products`, `dawn-poc-stub-core`,
`dawn-poc-stub-knowledge`, `dawn-poc-toolbox` — all `external: true` on the internal env
(VNet-reachable, not internet-facing), serving the placeholder image until real images ship.

_See `README.md`, `ARCHITECTURE.md`, `NETWORKING.md`, `OPERATIONS.md`, `GAP-CLOSURE.md`, and `security/README.md` for detail._
