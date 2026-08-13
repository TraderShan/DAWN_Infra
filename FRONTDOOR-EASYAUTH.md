# Front Door + WAF and EasyAuth — enablement & back-out runbook

This covers the two capabilities added to `dawn-infra`:

1. **Azure Front Door (Premium) + WAF** — a public, WAF-protected front on the otherwise-private **ui** app, reaching it over **Private Link** (no public IP on the container app).
2. **EasyAuth (Microsoft Entra ID)** — a sign-in gate on the **ui** app, enforced at ingress on **every** path (Front Door *and* the internal jumpbox/ILB path).

Both are **off by default in the code** and gated behind flags:

| Flag (Bicep / Terraform) | Default | What it does |
|---|---|---|
| `deployFrontDoor` / `deploy_front_door` | **true** in the active param files | Deploys AFD Premium + WAF + Private Link origin to the ui app |
| `wafMode` / `waf_mode` | `Prevention` | `Prevention` blocks; `Detection` only logs (tuning) |
| `wafRateLimitThreshold` / `waf_rate_limit_threshold` | `100` | Requests/min per client IP before the WAF blocks |
| `enableEasyAuth` / `enable_easy_auth` | **false** | Entra sign-in gate on the ui app |
| `easyAuthClientId` / `easy_auth_client_id` | `''` | App-registration (client) ID — filled in Phase 2 |
| `easyAuthClientSecret` / `easy_auth_client_secret` | env var | Client secret (never committed) |

> **Traffic flow (Front Door on):**
> `Internet → Front Door edge → WAF (DRS 2.1 + Bot Manager 1.1 + rate-limit) → Private Link (managedEnvironments) → internal ACA ILB → ui app`
> The existing internal path (jumpbox → `greenbay-*` private DNS → ILB → app) is **unchanged** — this *adds* an ingress path, it does not replace one.

---

## Why this is two-phase

EasyAuth's redirect URI is `https://<front-door-host>/.auth/login/aad/callback`. The Front Door host is a **hashed name** (e.g. `ep-dawn-poc-a1b2c3.z01.azurefd.net`) that does **not exist until Front Door is deployed**. So you cannot create the Entra app registration with the correct redirect URI up front.

- **Phase 1 — deploy Front Door** (`deployFrontDoor = true`, `enableEasyAuth = false`). This is the current default. Gets you the public WAF-protected host.
- **Phase 2 — turn on EasyAuth.** Create the app registration against the Phase-1 host, fill in the client ID, supply the secret, flip `enableEasyAuth = true`, redeploy.

---

## What the deployment does automatically

`./deploy.sh` (either engine) handles:

- ✅ Registers the **`Microsoft.Cdn`** resource provider (added to the provider list).
- ✅ Deploys the AFD profile, endpoint, origin group, **Private Link origin**, route, WAF policy, and the WAF↔endpoint security policy.
- ✅ Sets `publicNetworkAccess = Disabled` on the ACA environment (Bicep) — implicit in Terraform via `internal_load_balancer_enabled = true`.
- ✅ **Approves the Front Door Private Link connection** on the ACA environment after the deploy (polls up to ~3 min, then approves the pending connection).
- ✅ When EasyAuth is on: stores the client secret as a container-app secret and creates the `authConfigs/current` child resource on the ui app.

Everything below is the part the deployment **cannot** do for you.

---

## Manual steps — things to configure yourself

### A. Front Door (Phase 1) — usually nothing

Front Door is fully deployable with no prerequisites. The two things people forget are both automated in `deploy.sh`, but if you deploy the templates **directly** (not via `deploy.sh`), do them yourself:

1. **Register the CDN provider** (one-time per subscription):
   ```bash
   az provider register -n Microsoft.Cdn
   ```
2. **Approve the Private Link connection** on the ACA env (traffic won't flow until you do):
   ```bash
   ENV_ID=$(az resource list -g rg-dawn-fsi-poc \
     --resource-type Microsoft.App/managedEnvironments --query "[0].id" -o tsv)
   PEC=$(az network private-endpoint-connection list --id "$ENV_ID" \
     --query "[?properties.privateLinkServiceConnectionState.status=='Pending'].id" -o tsv)
   az network private-endpoint-connection approve --id "$PEC" --description "AFD"
   ```
   Portal equivalent: **ACA environment → Networking → Private endpoint connections → Approve**.

3. **Grab the public host** (Phase-2 input, and how you browse the app):
   ```bash
   # Bicep
   az deployment group show -g rg-dawn-fsi-poc -n <deployment-name> \
     --query properties.outputs.frontDoorEndpointHostName.value -o tsv
   # Terraform
   terraform -chdir=terraform output -raw front_door_endpoint_host_name
   ```
   Then browse `https://<that-host>`. Allow ~5–10 min after approval for the origin health probe to go green.

### B. EasyAuth (Phase 2) — the Entra app registration

This is the genuinely manual part — it creates **Microsoft Entra** objects, which the ARM/Bicep/Terraform deploy does not touch. You need permission to create app registrations in the tenant (or ask an admin).

```bash
# 0. The Phase-1 Front Door host from step A.3
AFD_HOST="ep-dawn-poc-xxxx.z01.azurefd.net"

# 1. Create the app registration (single-tenant) with the EasyAuth redirect URI
APP_ID=$(az ad app create \
  --display-name "Dawn UI (EasyAuth)" \
  --sign-in-audience AzureADMyOrg \
  --web-redirect-uris "https://${AFD_HOST}/.auth/login/aad/callback" \
  --query appId -o tsv)
echo "client id = $APP_ID"

# 2. EasyAuth uses the hybrid flow — enable ID-token issuance
az ad app update --id "$APP_ID" --set web.implicitGrant.idTokenIssuanceEnabled=true

# 3. Create a client secret (1-year); copy the value NOW — it is shown once
SECRET=$(az ad app credential reset --id "$APP_ID" \
  --display-name easyauth --years 1 --query password -o tsv)

# 4. Create the service principal (enterprise app) so sign-in/consent works
az ad sp create --id "$APP_ID"
```

Then wire it in and redeploy:

**Bicep**
```bash
# main.bicepparam:  enableEasyAuth = true   and   easyAuthClientId = '<APP_ID>'
export EASYAUTH_CLIENT_SECRET="$SECRET"
./deploy.sh -e bicep
```
**Terraform**
```bash
# terraform.tfvars:  enable_easy_auth = true   and   easy_auth_client_id = "<APP_ID>"
export TF_VAR_easy_auth_client_secret="$SECRET"
./deploy.sh -e terraform
```

### C. Optional but recommended

- **Grant users access.** Single-tenant means anyone in the MCAPS tenant can sign in by default. To restrict to specific people, set the enterprise app to **User assignment required** and add users/groups:
  `az ad sp update --id "$APP_ID" --set appRoleAssignmentRequired=true` (then assign users in **Entra → Enterprise applications → Dawn UI → Users and groups**).
- **External (B2B) users** need to be invited as guests into the tenant first.
- **Custom domain + TLS** (instead of the `*.azurefd.net` host): add the domain to the Front Door endpoint, create the DNS `CNAME` + `dnsauth` TXT records at your registrar, use an AFD **managed certificate**, then **add the custom-domain callback** `https://<custom-domain>/.auth/login/aad/callback` as a second redirect URI on the app registration.
- **Rotate the client secret** before it expires (1 year here). Re-run step B.3, re-export the env var, redeploy.
- **Lock down the direct ILB path.** EasyAuth already gates the ui app on every path. If you also want the *stubs/toolbox* reachable only through the ui, that's a separate change (per-app ingress or an internal-only `external: false`), not covered here.

---

## Verify it works

1. **WAF is protecting the endpoint** — a health/normal request succeeds; a probe with an attack signature is blocked:
   ```bash
   curl -s -o /dev/null -w "%{http_code}\n" "https://${AFD_HOST}/"                      # 200 (or 302 to login if EasyAuth on)
   curl -s -o /dev/null -w "%{http_code}\n" "https://${AFD_HOST}/?q=<script>alert(1)</script>"  # 403 (blocked by DRS)
   ```
2. **EasyAuth is enforced** — an unauthenticated browser is redirected to the Entra login; a token-less curl returns 401/302:
   ```bash
   curl -s -o /dev/null -w "%{http_code}\n" -L "https://${AFD_HOST}/"   # 302 -> login.microsoftonline.com
   ```
   From the **jumpbox**, the same curl to the internal `*.greenbay-*` FQDN should now also return 401/302 (EasyAuth is path-agnostic).
3. **Origin health is green** — Front Door endpoint → Origin groups → `og-ui` shows the origin healthy.

---

## Back-out / rollback

Both features are additive and independently reversible. Nothing here touches the data tier, Foundry, Fabric, or the existing Bastion/jumpbox access — the internal ILB path keeps working throughout.

### Roll back EasyAuth only (keep Front Door)

The app stops requiring sign-in; the WAF/Front Door front stays up.

- **Bicep:** set `enableEasyAuth = false` in `main.bicepparam` → `./deploy.sh -e bicep`.
- **Terraform:** set `enable_easy_auth = false` in `terraform.tfvars` → `./deploy.sh -e terraform`.

This removes the `authConfigs/current` resource and the container-app secret on the next deploy. (Manual immediate off-switch, no redeploy: `az containerapp auth update -g rg-dawn-fsi-poc -n dawn-poc-ui --unauthenticated-client-action AllowAnonymous`.)

The **Entra app registration is not deleted by IaC** — remove it by hand if you're done with it:
```bash
az ad app delete --id "$APP_ID"
```

### Roll back Front Door (and WAF)

Turning the flag off deletes the AFD profile, endpoint, origin group, origin, route, WAF policy, and security policy. Deleting the origin also tears down the Private Link connection on the ACA env.

- **Bicep:** set `deployFrontDoor = false` in `main.bicepparam` → `./deploy.sh -e bicep`.
- **Terraform:** set `deploy_front_door = false` in `terraform.tfvars` → `./deploy.sh -e terraform`.

> **Order matters:** if EasyAuth was configured against the Front Door host, roll **EasyAuth back first** (or at least remove the AFD redirect URI from the app registration), otherwise sign-in against that host breaks the moment Front Door is gone. If you keep EasyAuth on for the internal path, update the app registration's redirect URI accordingly.

After removal, confirm no orphaned Private Link connection remains on the env:
```bash
ENV_ID=$(az resource list -g rg-dawn-fsi-poc --resource-type Microsoft.App/managedEnvironments --query "[0].id" -o tsv)
az network private-endpoint-connection list --id "$ENV_ID" -o table   # expect none from AFD
```
If a stale connection lingers, remove it: `az network private-endpoint-connection delete --id <conn-id>`.

### Revert the ACA env `publicNetworkAccess` (Bicep, optional)

The env was already internal, so `publicNetworkAccess = Disabled` is a no-op you can leave in place. To revert the code anyway, remove the `publicNetworkAccess` line and restore the API version in `modules/containerapps-env.bicep` — but only after Front Door is gone (Private Link needs it).

### Full manual teardown (no redeploy)

If you want it gone immediately without an IaC pass:
```bash
# Front Door + WAF (RG-scoped)
az afd profile delete -g rg-dawn-fsi-poc -n afd-dawn-poc --yes
az network front-door waf-policy delete -g rg-dawn-fsi-poc -n wafdawnpoc

# EasyAuth off + secret removal
az containerapp auth update -g rg-dawn-fsi-poc -n dawn-poc-ui --unauthenticated-client-action AllowAnonymous
az containerapp secret remove -g rg-dawn-fsi-poc -n dawn-poc-ui --secret-names aad-client-secret
```
Then set the flags to `false` in the param files so the next IaC deploy doesn't recreate them (a deploy with the flags still `true` will bring them back).

---

## Cost & operational notes

- **Front Door Premium** carries a base monthly charge (~$330/mo list) plus request/data fees — materially more than Standard. Premium is **required** for Private Link origins and the managed WAF rule sets; Standard cannot reach a private ACA origin. If cost matters for a short demo, deploy it for the demo window and roll it back after (steps above).
- **WAF in `Detection`** first if you're unsure about false positives on the real UI, watch the Log Analytics `FrontDoorWebApplicationFirewallLog`, then switch to `Prevention`.
- **Private Link approval is one-time** per origin; it survives redeploys.
