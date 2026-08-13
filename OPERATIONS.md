# Operations — deploy safely, tear down cleanly

> **Region: Sweden Central — verify hosted agents + model in the Foundry portal before deploying.**
> Foundry hosted agents (the BYO-VNet runtime this template uses) roll out to fewer regions
> than the published Responses-API list, so a region can be "on the list" and still lack them
> (that's what happened with West US 3). Before you run the deploy, open the Foundry portal and
> confirm Sweden Central appears in the project-creation region dropdown, and that your models
> (`gpt-5.4` + `text-embedding-3-large`, both enabled) are offered there. VNet and Foundry must share the region.

Private networking on Foundry is powerful but has runtime-only failure modes. A deployment
can go green in the portal and the **first agent tool call still fails**. Budget time for
this, and validate end to end with a real tool call early rather than trusting a clean
deploy. (Straight from Section 9 of the Infrastructure doc.)

## Before you deploy

1. **Create the Foundry project fresh.** Projects created after 2026-06-25 get private-ACR
   support (public access disabled + private endpoint), which this template assumes. Don't
   reuse an old project.
2. **Confirm the region** supports Foundry hosted agents, and that VNet + Foundry are
   co-located (`swedencentral` by default).
3. **Check IP non-overlap.** `192.168.0.0/16` must not overlap peered networks or reserved
   ranges.
4. **Run preflight.** Use Microsoft's private-Foundry preflight/validation script and
   testing guide before assuming green = working.
5. **Validate the IaC:** `az bicep build main.bicep` or `terraform validate`, then a
   what-if / plan.

## Preview API surface to verify

These use **preview** shapes that move quickly — check them against the current *Foundry
Agent Service – Standard / BYO-agent-tools* references at build time:

- `Microsoft.CognitiveServices/accounts` → `properties.networkInjections` (agent subnet)
- `…/accounts/projects/connections@2025-04-01-preview`
- `…/accounts/projects/capabilityHosts@2025-04-01-preview`

If Microsoft has revised these, update `modules/foundry.bicep`,
`modules/foundry-capabilityhost.bicep`, and `terraform/foundry.tf` (the `azapi_resource`
bodies) accordingly. Consider starting from Microsoft's published reference Bicep/Terraform
for the BYO-agent-tools ("template 19") pattern and grafting these modules onto it.

## The four failure modes to expect

| Symptom | Cause | Guard in this template / what to do |
|---------|-------|-------------------------------------|
| Deploy passes, first tool call fails | Runtime state (missing role, unlinked DNS, capability host in failed state) | Test a real tool call early; check each item below |
| Capability host creation fails | RBAC not propagated when it ran | **Handled**: capability host is a separate module deployed after `rbac`. If it still races, re-run the deployment (idempotent) |
| Capability host fails: `...sqlDatabases/read` not authorized | Project identity lacks **control-plane** rights to create the `enterprise_memory` DB in your BYO Cosmos | **Handled**: the RBAC module grants the project the **Cosmos DB Operator** role on the Cosmos account (in addition to the data-plane Built-in Data Contributor) |
| PE approved but lookups hit public IP | Private DNS zone not linked to the VNet | Zones + links are provisioned; **validate DNS resolution from inside the VNet** (e.g. from a Bastion-reached VM) |
| Redeploy fails with a stuck subnet | Teardown ran out of order (orphaned Service Association Link) | Tear down in reverse — see below |

## Teardown ordering

The dependency chain is **VNet → delegated subnet → Foundry account → capability host →
project**. Tear down in reverse, or a redeploy fails on a stuck subnet:

1. Capability host → project → model deployments → connections
2. Foundry account (releases the agent subnet's Service Association Link)
3. ACA apps/jobs → ACA environment
4. Private endpoints → data resources (Cosmos, Search, Storage, KV, ACR)
5. Bastion → VNet
6. Fabric capacity, Log Analytics / App Insights, managed identity

Practical options:
- **Bicep:** delete the whole resource group (`az group delete -n rg-dawn-fsi-poc`) — ARM
  resolves order. If a subnet gets stuck, delete the Foundry account first, then retry.
- **Terraform:** `terraform destroy`. The `depends_on` edges (capability host → rbac,
  compute → rbac) drive teardown in the right order.

> **Soft-deleted resources block name reuse.** Both **Key Vault** and the **Foundry
> (Cognitive Services) account** have soft-delete enabled. Resource names are derived from
> the resource-group ID (`uniqueString(...)`), so deleting and recreating the *same* RG
> name yields the *same* names — and the soft-deleted copies will block the redeploy until
> purged (see the redeploy steps below).

## Redeploying an existing, healthy environment (incremental re-run)

Re-running the full template against an environment that's **already up** trips over a few
resources that can't be re-applied in place. Set one switch and it's clean:

- **`agentStackDeployed = true`** (`agent_stack_deployed = true` in Terraform) — **set this
  on every redeploy after the first successful one.** Once the Foundry **capability host**
  is created, it *locks* the three agent connections (`cosmos-thread-store`,
  `storage-file-store`, `aisearch-knowledge`); re-writing them through the connections API
  fails (`Connection '…' is in use by the workspace capability host`). This switch skips the
  connections + capability host (they already exist and keep working).
- **Jumpbox OS disk** — the template no longer forces the disk SKU, so redeploys won't hit
  *"Managed disk storage account type change … is not allowed."* (Terraform is state-aware,
  so it was never affected.)
- **Fabric "Service is not ready to be updated"** — transient; the capacity exists and is
  fine. Just re-run; it applies once the capacity finishes settling.

None of these mean anything is broken — they're the cost of re-running an all-in-one
template over live resources. With `agentStackDeployed = true`, a redeploy re-applies the
safe resources (compute, networking, RBAC, etc.) and leaves the locked agent stack alone.

> **Terraform note — flip the flag on redeploy only.** The shipped `terraform.tfvars.example`
> defaults **`agent_stack_deployed = false`**, which is correct for a *first / fresh* deploy
> (it creates the connections + capability host). If you are **redeploying with Terraform
> against an environment whose agent stack already exists**, set **`agent_stack_deployed = true`**
> in your `terraform.tfvars` before `apply` — otherwise the run fails with
> `Connection '…' is in use by the workspace capability host`. This mirrors the Bicep
> `agentStackDeployed` flag exactly; only the variable name differs. Both are already set for
> this deployed environment — `main.bicepparam` (Bicep) and the provided `terraform.tfvars`
> (Terraform) are both `true`. The shipped `.example` stays `false` as the first-deploy default.

## Redeploying after a failed or torn-down deployment

Names are deterministic per resource-group ID, so you have two clean-slate paths:

### Option 1 — New resource group name (simplest, no purging)
A different RG → a different `uniqueString` suffix → brand-new names, so nothing collides:

```bash
RESOURCE_GROUP=rg-dawn-fsi-poc2 bash deploy.sh --engine bicep --what-if-only   # preview
RESOURCE_GROUP=rg-dawn-fsi-poc2 bash deploy.sh --engine bicep                  # deploy
```

### Option 2 — Reuse the same RG name (purge the two soft-deleted resources first)

```bash
az group delete -n rg-dawn-fsi-poc --yes

# Purge the soft-deleted resources that keep their names (replace <suffix> with the
# value from your names, e.g. kvdawn<suffix> / aif-dawn-poc-<suffix>):
az keyvault purge --name kvdawn<suffix> --location swedencentral
az cognitiveservices account purge --name aif-dawn-poc-<suffix> \
  --resource-group rg-dawn-fsi-poc --location swedencentral

bash deploy.sh --engine bicep --what-if-only
bash deploy.sh --engine bicep
```

> If `az group delete` stalls on the VNet/subnet (orphaned Service Association Link from
> the agent subnet), delete the **Foundry account first**, then retry the group delete.

**Terraform:** prefer `terraform destroy` (it tears down in dependency order via the
`depends_on` edges), then re-`apply`. Terraform owns its resource group, so don't
pre-create or manually delete it out from under the state.

After either option, the `--what-if-only` / `--plan-only` preview should show the **Cosmos
DB Operator** assignment among the RBAC resources — that's the fix that lets the capability
host create its `enterprise_memory` database.

## Cost

Fabric F4, Premium ACR, Bastion, and any model deployment bill continuously. **Pause the
Fabric capacity when idle.** A full cost/sizing pass (ACA, hosted-agent runtime, Cosmos,
Search, OneLake/Fabric, model usage) is worth doing as its own artifact — flagged in the
doc's open questions, not done here.

## After deploy

1. `build-and-push-apps` → push real UI/stub/agent images to ACR.
2. Point `containerApps[*].image` (and the job images) at the ACR tags, redeploy.
3. Configure the Foundry IQ knowledge base over AI Search, curate Toolbox tools, and pick
   managed vs BYO (Cosmos `conversations`) memory.
4. Reach the UI and tools through **Bastion** (there is no public endpoint).

## Connecting via the jumpbox (Entra login)

The optional Windows jumpbox in `snet-mgmt` is the management host external users reach
through Bastion. It's **off by default** — enable it when you need in-VNet access (to hit
the internal ACA apps, private endpoints, the Foundry portal, or validate private DNS).

**Enable it:**
1. Set `deployJumpbox = true` (Bicep) / `deploy_jumpbox = true` (Terraform). *(Already set in
   the shipped param files.)*
2. Supply the local-admin password via an **environment variable** — never committed to
   source. The param files read it at deploy time (`readEnvironmentVariable(...)` in the
   `.bicepparam`; `TF_VAR_...` in Terraform), so `deploy.sh` needs **no extra switches**.
   Set the variable in the **same shell**, then run your usual deploy command:

   ```bash
   # Bicep
   export JUMPBOX_ADMIN_PASSWORD='<StrongP@ssw0rd!>'
   ./deploy.sh --engine bicep --yes

   # Terraform
   export TF_VAR_jumpbox_admin_password='<StrongP@ssw0rd!>'
   ./deploy.sh --engine terraform
   ```

   - Use **single quotes** so shell metacharacters (`!`, `$`, `#`) aren't interpreted.
   - To keep the password out of shell history, prompt for it instead:
     `read -s -p "pw: " JUMPBOX_ADMIN_PASSWORD; export JUMPBOX_ADMIN_PASSWORD; echo`
   - PowerShell calling bash: `$env:JUMPBOX_ADMIN_PASSWORD='<pw>'` then `bash ./deploy.sh …`.
   - If the variable is unset, the password resolves to empty and the Windows VM deploy
     **fails** — that's the only failure mode. Password rules: 12–123 chars, 3 of 4 of
     {upper, lower, digit, special}, not equal to the username.
3. Redeploy. Requires **Bastion deployed** (`deployBastion = true`, the default) and
   Owner / User Access Administrator to create the VM-login role assignment.

**Image note:** the jumpbox uses plain **Windows Server 2022 Datacenter (Gen2)**, not the
*Azure Edition* SKU — Azure Edition's strict attestation can pop *"…deactivated because you
are not running on Azure…"*. The VM image is **immutable**, so changing it means recreating
the VM:
- **Bicep:** delete the VM **and its OS disk** first, then redeploy —
  `az vm delete -g rg-dawn-fsi-poc -n vm-jump-dawn-poc --yes`, then delete the
  `vm-jump-dawn-poc_OsDisk_*` disk. (New VMs set `deleteOption: Delete`, so future deletes
  clean the disk automatically.) The NIC/NSG can stay — the template re-applies them.
- **Terraform:** `terraform apply` detects the image change as a **replacement** and
  destroys + recreates the VM automatically — just confirm the plan.

**Connect — Option A: Portal (simplest, works with no extra config):**
- Open the VM → **Connect → Bastion**, choose **Azure AD (Entra)** authentication, and sign
  in as your **MCAPS-tenant** account: `shannichols@MngEnvMCAP776009.onmicrosoft.com` —
  **not** the corp `@microsoft.com` one. Entra VM login authenticates against the
  subscription's tenant (MCAPS), so the corp identity won't work (same reason it failed as
  the Fabric admin).
- The `AADLoginForWindows` extension + the **Virtual Machine Administrator Login** role
  (granted to your MCAPS object ID `9e631dcf-…`) provide admin RDP rights.
- Local admin (`azureadmin` + password) still works as a fallback.

**Connect — Option B: CLI native client (`az network bastion rdp`):**
- Requires **Standard SKU + native-client tunneling enabled**. The template sets this
  (`enableTunneling` / `tunneling_enabled` = true whenever the SKU is Standard, the
  default) — so redeploy once after enabling it before using this path.
- `az network bastion rdp` launches `mstsc`, so it runs from a **Windows** machine only.
  On macOS/Linux use `az network bastion tunnel --resource-port 3389 --port 50000` and
  point your RDP client at `localhost:50000`.
- Use **straight quotes** and the **full VM resource ID** (not the VM name — a common error):
  ```bash
  VMID=$(az vm show -g rg-dawn-fsi-poc -n vm-jump-dawn-poc --query id -o tsv)
  az network bastion rdp --name "bas-dawn-poc" --resource-group "rg-dawn-fsi-poc" \
    --target-resource-id "$VMID"
  ```
- In the RDP credential prompt: for Entra login enter
  `AzureAD\shannichols@MngEnvMCAP776009.onmicrosoft.com`; for local admin use `azureadmin`.

**Bastion SKU note:** Bastion is **Standard** (`bastionSku = 'Standard'`), which enables both
Entra auth and native client. Upgrading an existing Basic Bastion to Standard happens in
place on redeploy; you can't later downgrade.

## Verifying a Container App from the jumpbox

The apps are **internal** — only reachable from inside the VNet (the jumpbox), never from
your laptop. Follow this exact order; most "can't reach / 404" dead-ends here were a
slightly-wrong hostname typed by hand.

**1. Get ground truth (Cloud Shell / local machine — needs the right subscription):**
```bash
# If you hit "ResourceGroupNotFound", your context is on the wrong subscription/tenant:
az account set --subscription 3a8f035c-5882-4df8-90f7-eb11a8bda066

# The EXACT fqdn + external flag + port (copy the fqdn verbatim — don't type it):
az containerapp show -g rg-dawn-fsi-poc -n dawn-poc-ui \
  --query "properties.configuration.ingress.{external:external, fqdn:fqdn, targetPort:targetPort}" -o json
# The env's internal IP (DNS must point here):
az containerapp env show -g rg-dawn-fsi-poc -n cae-dawn-poc \
  --query "{staticIp:properties.staticIp, state:properties.provisioningState}" -o json
```
Expect `external: true`, an fqdn **without** `.internal.`, `targetPort` matching your image's
port, and `staticIp: 192.168.2.27` (example), `state: Succeeded`.

**2. Test from the jumpbox (paste the exact fqdn — never hand-type it):**
```powershell
$fqdn = "<paste exact fqdn from step 1>"
ipconfig /flushdns
Resolve-DnsName $fqdn          # must return the env static IP (e.g. 192.168.2.27)
curl.exe -k "https://$fqdn/"   # expect the app's page
```

**Reading the results:**
| Symptom | Cause | Fix |
|---------|-------|-----|
| `Resolve-DnsName` → *does not exist* | ACA Private DNS zone missing/unlinked | The template auto-creates it now; on older deploys add zone = env `defaultDomain`, `*` A → static IP, VNet link |
| Resolves to static IP, curl → **"…stopped or does not exist"** | app ingress is `external: false` (env-internal only), **or** wrong image port | Set `external: true` (`az containerapp ingress enable --type external --target-port <port>`); confirm the image's listening port matches `targetPort` |
| Resolves + curl works by IP but browser fails | browser cache | InPrivate window / Ctrl+F5 |
| `curl: Could not resolve host` | hostname typo (e.g. missing the region label) | copy the fqdn from step 1 verbatim |

> Cloud Shell is **not** in the VNet, so it can't `curl` the internal FQDN — only the jumpbox
> (or another in-VNet host) can. `az` management commands run from Cloud Shell; `curl` runs
> from the jumpbox.
