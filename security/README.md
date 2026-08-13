# Microsoft Defender for Cloud (optional, subscription-scoped)

Enables Defender for Cloud **threat-protection plans** for the resource types Dawn uses.
Kept **separate** from the main infra template on purpose.

## ⚠️ Read first — this is subscription-wide
- Defender plans are enabled at the **subscription level**, not the resource group. Turning
  on "Defender for Storage" protects **every** storage account in subscription
  `3a8f035c-…`, not just Dawn's — and **billing applies to all of them**.
- If that subscription is shared, coordinate before enabling.
- Each plan bills per resource (per server/hour, per storage account, etc.). There's
  usually a **30-day free trial** per plan. Check current pricing before committing.
- You need **Security Admin** or **Owner** at the subscription scope.

## Plans enabled
| Plan (`resource_type` / pricing name) | Protects |
|---|---|
| `VirtualMachines` (sub-plan **P2**) | Defender for Servers — the jumpbox |
| `StorageAccounts` (**DefenderForStorageV2**) | Defender for Storage — malware + activity |
| `KeyVaults` | Defender for Key Vault |
| `CosmosDbs` | Defender for Cosmos DB |
| `Containers` | Defender for Containers — ACR image scanning |
| `Arm` | Defender for Resource Manager (control plane) |
| `AI` | Defender for AI Services — Foundry / Azure OpenAI *(newer plan — see note)* |

> **`AI` plan note:** it's included in the Bicep `plans` param but **commented out in the
> Terraform** (the azurerm provider may not accept `"AI"` yet). If Terraform is your engine,
> enable it separately: `az security pricing create -n AI --tier Standard`.

## Deploy

### Bicep (subscription-scoped)
```bash
az account set --subscription 3a8f035c-5882-4df8-90f7-eb11a8bda066
az deployment sub create \
  --location swedencentral \
  --template-file defender.bicep \
  --parameters securityContactEmail='shannichols@MngEnvMCAP776009.onmicrosoft.com'
```
*(`--location` is only for deployment metadata; Defender plans are subscription-global.)*

### Terraform (own state — run from this `security/` folder)
```bash
export ARM_SUBSCRIPTION_ID=3a8f035c-5882-4df8-90f7-eb11a8bda066
terraform init
terraform apply -var security_contact_email='shannichols@MngEnvMCAP776009.onmicrosoft.com'
```

### Quickest (no IaC) — Azure CLI
```bash
for p in VirtualMachines StorageAccounts KeyVaults CosmosDbs Containers Arm AI; do
  az security pricing create -n "$p" --tier Standard
done
```

Verify in the portal: **Defender for Cloud → Environment settings → your subscription** —
plans show **On**; alerts + Secure Score populate within a few hours.

## Back out (disable everything)

### Terraform
```bash
terraform destroy   # reverts every plan to Free and removes the security contact
```

### Bicep or CLI (set each plan back to Free)
Bicep can't "destroy" a subscription deployment, so revert with the CLI:
```bash
for p in VirtualMachines StorageAccounts KeyVaults CosmosDbs Containers Arm AI; do
  az security pricing create -n "$p" --tier Free
done
# remove the alert contact if you created one:
az security contact delete -n default
```

### Or the portal
**Defender for Cloud → Environment settings → your subscription** → toggle each plan **Off** → **Save**.

Reverting to **Free** keeps the free CSPM (Secure Score, recommendations) — it only turns
off the paid threat-detection layer and its billing.
