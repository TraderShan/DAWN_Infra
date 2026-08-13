# Prerequisites — before running `deploy.sh`

You do **not** need to pre-deploy anything in Azure. `deploy.sh` creates the resource group
and every resource itself (Terraform creates its own resource group). What you need is the
right access, tools, and a couple of confirmations. Work top to bottom.

## 1. Local tools
- [ ] **Azure CLI (`az`)** installed and signed in: `az login`. The script refuses to run otherwise.
- [ ] **Terraform ≥ 1.5** — only if you use `--engine terraform`.
- [ ] Correct subscription selected: `az account set --subscription <id>` (or pass `SUBSCRIPTION=<id>`).

## 2. Azure permissions (most common failure point)
- [ ] **Owner** or **User Access Administrator** on the target subscription/resource group.
      The template creates **role assignments** (RBAC + Cosmos data-plane roles) — plain
      **Contributor is not enough** and the deploy fails partway through on the RBAC step.
- [ ] Permission to **register resource providers**. `deploy.sh` registers them for you, but
      that needs Contributor+ at the subscription. Otherwise have an admin pre-register the
      providers the script lists (Microsoft.App, CognitiveServices, DocumentDB, Search,
      Fabric, etc.).

## 3. Confirm in the subscription + Sweden Central
- [ ] **Foundry hosted agents available in Sweden Central** — verify in the Foundry portal
      (project-creation region dropdown). This is the exact check that failed for West US 3.
- [ ] **Microsoft Fabric enabled / F-SKU creation allowed.** The **F4** capacity bills
      immediately once created — pause it when idle.
- [ ] **Public IP allowed.** Azure **Bastion** needs a Standard public IP; ensure no Azure
      Policy blocks public IP creation.
- [ ] **Models enabled** — chat `gpt-5.4` + embedding `text-embedding-3-large` deploy at 100K
      TPM each. Each draws from its own 1M-TPM GlobalStandard pool, so **no quota request is
      needed**; just confirm both models are offered in Sweden Central.

## 4. Fill in required parameters
- [ ] `fabricAdminMembers` (Bicep `main.bicepparam`) / `fabric_admin_members` (Terraform
      `terraform.tfvars`) — a valid UPN or Entra object ID, or the Fabric step fails.
- [ ] *(optional)* `testerPrincipalId` / `tester_principal_id` — your Entra object ID for
      hands-on data access: `az ad signed-in-user show --query id -o tsv`.

## 5. Deploy
```bash
# Preview first (no changes)
bash deploy.sh --engine bicep --what-if-only
# or
bash deploy.sh --engine terraform --plan-only

# Then deploy
bash deploy.sh --engine bicep
# or
bash deploy.sh --engine terraform
```

## Good to know
- **No ACR images needed for the first deploy.** Apps run the public MCR placeholder image;
  push real images (via the `build-and-push-apps` workflow) and repoint later.
- **Resource-group creation differs by engine:** Bicep — `deploy.sh` creates `rg-dawn-fsi-poc`.
  Terraform — **do not pre-create it**, Terraform owns it.
- **Run end-to-end validation early.** Private Foundry can deploy green and still fail the
  first agent tool call — see `OPERATIONS.md` for the failure modes and teardown order.

## Only for the GitHub Actions pipelines (not needed for `deploy.sh`)
- [ ] An **Entra app registration with OIDC federated credentials** for the repo.
- [ ] Repo **secrets**: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`.
- [ ] Repo **variables**: `ACR_NAME`, `RESOURCE_GROUP` (optional; defaults exist).

## Team / repo hygiene
- [ ] `.gitignore` is included — do not commit Terraform state or real `terraform.tfvars`.
- [ ] For shared use, point Terraform at a **remote state backend** (azurerm backend on a
      storage account). As written it uses local state — fine for a solo first run, not for
      a team.
