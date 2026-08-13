#!/usr/bin/env bash
# =====================================================================================
#  deploy.sh - Dawn private infrastructure deployment wrapper
# -------------------------------------------------------------------------------------
#  Deploys the environment with EITHER Bicep or Terraform, your choice.
#
#  Usage:
#    ./deploy.sh --engine bicep                 # build -> what-if -> confirm -> deploy
#    ./deploy.sh --engine terraform             # init -> plan -> confirm -> apply
#    ./deploy.sh --engine bicep --what-if-only  # preview only (bicep)
#    ./deploy.sh --engine terraform --plan-only # preview only (terraform)
#    ./deploy.sh --engine bicep --yes           # skip confirmation
#
#  Override defaults via env vars:
#    RESOURCE_GROUP=rg-dawn LOCATION=swedencentral SUBSCRIPTION=<sub-id> ./deploy.sh -e bicep
# =====================================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ENGINE=""
ASSUME_YES=false
PREVIEW_ONLY=false

RESOURCE_GROUP="${RESOURCE_GROUP:-rg-dawn-fsi-poc}"
LOCATION="${LOCATION:-swedencentral}"
SUBSCRIPTION="${SUBSCRIPTION:-}"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-dawn-$(date +%Y%m%d-%H%M%S)}"
TEMPLATE="${SCRIPT_DIR}/main.bicep"
PARAMS="${SCRIPT_DIR}/main.bicepparam"
TF_DIR="${SCRIPT_DIR}/terraform"
REGISTER_PROVIDERS="${REGISTER_PROVIDERS:-true}"

PROVIDERS=(
  Microsoft.ManagedIdentity Microsoft.Network Microsoft.OperationalInsights
  Microsoft.Insights Microsoft.Storage Microsoft.DocumentDB Microsoft.Search
  Microsoft.KeyVault Microsoft.ContainerRegistry Microsoft.CognitiveServices
  Microsoft.App Microsoft.Web Microsoft.Fabric Microsoft.Cdn
)

# ------------------------------- Arguments -------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -e|--engine)       ENGINE="${2:-}"; shift 2 ;;
    --engine=*)        ENGINE="${1#*=}"; shift ;;
    -y|--yes)          ASSUME_YES=true; shift ;;
    -w|--what-if-only|--plan-only) PREVIEW_ONLY=true; shift ;;
    -h|--help)         grep '^#' "$0" | sed 's/^# \{0,1\}//' | head -n 20; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!  %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mx  %s\033[0m\n' "$*" >&2; exit 1; }

confirm() {
  [[ "$ASSUME_YES" == "true" ]] && return 0
  printf '\n\033[1;33m%s [y/N] \033[0m' "$1"
  read -r reply
  case "$reply" in y|Y|yes|YES) return 0 ;; *) die "Aborted by user. Nothing was deployed." ;; esac
}

# When Front Door is deployed, its shared Private Link leaves a PENDING private-endpoint
# connection on the ACA managed environment. Traffic does NOT flow until it is approved.
# This finds and approves it automatically. Safe no-op when Front Door isn't deployed.
approve_afd_private_link() {
  local afd env_id pec_ids
  afd="$(az resource list -g "$RESOURCE_GROUP" --resource-type Microsoft.Cdn/profiles --query "[0].name" -o tsv 2>/dev/null || true)"
  [[ -z "$afd" ]] && return 0 # no Front Door in this RG -> nothing to approve

  say "Approving Front Door Private Link connection on the ACA environment"
  env_id="$(az resource list -g "$RESOURCE_GROUP" --resource-type Microsoft.App/managedEnvironments --query "[0].id" -o tsv 2>/dev/null || true)"
  [[ -z "$env_id" ]] && { warn "No ACA environment found in ${RESOURCE_GROUP}; skipping."; return 0; }

  # AFD may take a moment to create the pending connection — poll briefly.
  for _ in $(seq 1 12); do
    pec_ids="$(az network private-endpoint-connection list --id "$env_id" \
      --query "[?properties.privateLinkServiceConnectionState.status=='Pending'].id" -o tsv 2>/dev/null || true)"
    [[ -n "$pec_ids" ]] && break
    sleep 15
  done

  if [[ -z "$pec_ids" ]]; then
    warn "No pending Private Link connection found (already approved, or not yet surfaced)."
    warn "If Front Door shows an origin/health error, approve it in the portal: ACA env > Networking > Private endpoint connections."
    return 0
  fi

  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    echo "  approving $id"
    az network private-endpoint-connection approve --id "$id" \
      --description "Approved for Azure Front Door (Dawn ui)" --output none || warn "Approve failed for $id"
  done <<< "$pec_ids"
}

# ------------------------------- Engine selection ------------------------------------
if [[ -z "$ENGINE" ]]; then
  printf 'Choose deployment engine [bicep/terraform]: '
  read -r ENGINE
fi
ENGINE="$(echo "$ENGINE" | tr '[:upper:]' '[:lower:]')"
[[ "$ENGINE" == "bicep" || "$ENGINE" == "terraform" ]] || die "Engine must be 'bicep' or 'terraform'."

command -v az >/dev/null 2>&1 || die "Azure CLI ('az') not found. Install: https://aka.ms/azure-cli"
az account show >/dev/null 2>&1 || die "Not signed in. Run 'az login' first."
if [[ -n "$SUBSCRIPTION" ]]; then
  say "Setting subscription: $SUBSCRIPTION"
  az account set --subscription "$SUBSCRIPTION"
fi

if [[ "$REGISTER_PROVIDERS" == "true" ]]; then
  say "Registering resource providers (idempotent)"
  for p in "${PROVIDERS[@]}"; do
    state="$(az provider show -n "$p" --query registrationState -o tsv 2>/dev/null || echo NotFound)"
    [[ "$state" == "Registered" ]] || { echo "  registering $p ..."; az provider register -n "$p" >/dev/null || warn "Could not register $p."; }
  done
fi

# =====================================================================================
#  BICEP
# =====================================================================================
if [[ "$ENGINE" == "bicep" ]]; then
  say "Engine: Bicep  |  RG: ${RESOURCE_GROUP}  |  Location: ${LOCATION}"
  [[ -f "$TEMPLATE" ]] || die "Template not found: $TEMPLATE"

  say "Validating (az bicep build)"
  az bicep build --file "$TEMPLATE" --stdout >/dev/null && echo "Compiled OK." || die "Template failed to compile."

  say "Ensuring resource group '${RESOURCE_GROUP}'"
  az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none

  say "Previewing changes (what-if)"
  az deployment group what-if -g "$RESOURCE_GROUP" -n "$DEPLOYMENT_NAME" -f "$TEMPLATE" -p "$PARAMS"

  [[ "$PREVIEW_ONLY" == "true" ]] && { say "Preview only. Nothing deployed."; exit 0; }
  confirm "Proceed with Bicep deployment to ${RESOURCE_GROUP}?"

  say "Deploying (20-40 min; Foundry + Fabric are the slow parts)"
  az deployment group create -g "$RESOURCE_GROUP" -n "$DEPLOYMENT_NAME" -f "$TEMPLATE" -p "$PARAMS" --output none

  say "Outputs"
  az deployment group show -g "$RESOURCE_GROUP" -n "$DEPLOYMENT_NAME" --query properties.outputs -o json
fi

# =====================================================================================
#  TERRAFORM
# =====================================================================================
if [[ "$ENGINE" == "terraform" ]]; then
  say "Engine: Terraform  |  dir: ${TF_DIR}"
  command -v terraform >/dev/null 2>&1 || die "Terraform not found. Install: https://developer.hashicorp.com/terraform/install"
  [[ -d "$TF_DIR" ]] || die "Terraform directory not found: $TF_DIR"
  export ARM_SUBSCRIPTION_ID="${SUBSCRIPTION:-$(az account show --query id -o tsv)}"

  say "terraform init"
  terraform -chdir="$TF_DIR" init -input=false

  say "terraform validate"
  terraform -chdir="$TF_DIR" validate

  say "terraform plan"
  terraform -chdir="$TF_DIR" plan -input=false -out=tfplan

  [[ "$PREVIEW_ONLY" == "true" ]] && { say "Plan only. Nothing applied."; exit 0; }
  confirm "Proceed with Terraform apply?"

  say "terraform apply"
  terraform -chdir="$TF_DIR" apply -input=false tfplan

  say "Outputs"
  terraform -chdir="$TF_DIR" output
fi

# Approve the Front Door -> ACA Private Link (no-op if Front Door isn't deployed). Only
# reached after a real deploy — the preview paths (--what-if-only / --plan-only) exit earlier.
approve_afd_private_link

say "Done."
echo "Tip: pause the Fabric capacity when idle to stop its charges. Access the private apps via Azure Bastion."
echo "Tip: if Front Door is on, browse the ui at the frontDoorEndpointHostName output (https://<host>)."
