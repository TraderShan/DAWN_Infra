# Deployment Lessons Learned

## Deployment Ordering and Redeploy Traps

- **The Foundry capability host needs the Cosmos DB Operator role.** Agent thread-store provisioning fails at runtime without it: the deployment appears successful, then breaks. RBAC must be deployed before the capability host.
- **Set `agentStackDeployed = true` on every redeploy.** Once the Foundry agent stack and connections exist, they are locked. Redeploying with this value set to `false` throws `connection in use by the workspace capability host`.
- **Resume Fabric before any redeploy.** A paused capacity returns `Service is not ready to be updated`. This caused repeated failures.
- **Fabric's `Service is not ready` error is often transient.** Even when the capacity is not paused, waiting a few minutes and retrying may resolve it.

## Foundry and Models

- **Model-version preflight validation is stricter than runtime validation.** Version `2025-03-05` runs successfully as an existing deployment but fails preflight validation for new deployments. Keep `deployModel = false` until you select a currently supported version using `az cognitiveservices account list-models`.
- **Disabling `deployModel` does not delete the live model.** Incremental deployments leave resources that are no longer in the template untouched. The model continues running but becomes unmanaged by the template.
- **TPM quota is a rate limit, not a token pool.** It is allocated per model; each model had its own 1M-token-per-minute quota rather than sharing one bucket. Global Standard quota is separate from regional Standard quota.

## Region and Identity (MCAPS-Specific)

- **Foundry hosted agents are not available in every region.** West US 3 did not support them despite appearing on the published Responses API region list, so the deployment moved to Sweden Central. Verify availability in the Foundry portal rather than relying only on documentation.
- **Use the MCAPS identity everywhere, not the corporate identity.** Fabric administration, VM Entra sign-in, and RBAC require the `...@MngEnvMCAP...onmicrosoft.com` identity and object ID, not the `@microsoft.com` guest identity in the MCAPS tenant.
- **A Fabric administrator must be specified by UPN, not object ID.** Unlike normal RBAC, Fabric user administrators require the native-tenant UPN. Object IDs work only for service principals.
- **All Fabric administrators must be in the capacity's home tenant.** A corporate identity fails with `all administrators must belong to the same tenant`.

## Networking

- **A VNet defined with inline subnets prunes anything not in the template.** An out-of-band `GatewaySubnet` and VPN gateway caused `InUseSubnetCannotBeDeleted` on every deployment. Add the external resources to the template or remove them.
- **ACA private DNS zone links can conflict.** A zone can link to a VNet only once. Links left behind by partial deployments cause a `Conflict`; delete the stale link before redeploying.
- **Default outbound internet access was retired in September 2025.** A private VM or subnet has no outbound access without a NAT gateway, which is why the jumpbox could not reach the internet.
- **A NAT gateway is not required for ACA image pulls.** The ACA platform handles image pulls. NAT was needed only for jumpbox and application outbound traffic.

## Container Apps Ingress

- **`external: true` in an internal environment means VNet-reachable, not internet-facing.** The original `external: false` setting made applications reachable only from within the ACA environment, so requests from the jumpbox returned 404 responses. This was the root cause of a long debugging chain.
- **`.internal.` in an ACA FQDN means environment-only access.** Changing ingress to `external: true` removes `.internal.` and makes the application reachable from the VNet through the internal load balancer while keeping it private.
- **ACA does not automatically create its private DNS zone.** Add the zone, a wildcard record, and a VNet link. Use `*.internal`; the wildcard matches one label.
- **The placeholder image and `targetPort` must match.** The quickstart image does not listen on port `8000`; use port `80` for the `helloworld` image, then change it back to the application's actual port later.
- **Copy `main.bicep` and `main.bicepparam` together.** Deploying with a stale parameter file silently omitted features: Front Door did not deploy and EasyAuth parameters were missing, without producing an error.

## Front Door and EasyAuth

- **Front Door Premium is required for private ACA origins.** Standard cannot reach a Private Link origin. The Premium tier has an approximate base cost of $330 per month.
- **Approve the Private Link connection.** Front Door creates a pending connection on the ACA environment, and traffic will not route until it is approved. [`deploy.sh`](deploy.sh) automates this step.
- **Allow 5-10 minutes for the origin health probe.** A 503 response immediately after deployment usually means the probe is not healthy yet rather than indicating a deployment failure.
- **EasyAuth behind Front Door can generate incorrect redirect URIs.** Front Door rewrites the `Host` header, so the application sees its internal hostname and creates a redirect URI that Entra does not recognize, resulting in `AADSTS50011`. `--proxy-convention Standard` with `X-Forwarded-Host` header injection is intended to address this but was unreliable over Private Link. A custom domain was the robust fix, although it may be excessive for a proof of concept.
- **`--proxy-convention Standard` requires a new revision.** The configuration may show `Standard` while the active replica still uses the previous setting.
- **`AllowAnonymous` did not stop the 401 response.** EasyAuth middleware continued issuing a Bearer challenge until the middleware was fully disabled with `--enabled false`.
- **Test with both `curl` and a browser.** `curl -L` follows redirects to a 200 login page, which can look like success. A bare `curl` request may trigger WAF bot rules, while cached browser sessions can make behavior appear inconsistent. Test with a bare `curl` request without `-L` and a fresh incognito browser session.

## WAF and IP Allow-Lists

- **Use `RemoteAddr`, not `SocketAddr`, for the client IP in Front Door WAF.** Fall back to `SocketAddr` if blocking behaves incorrectly.
- **Detection mode does not block traffic.** Use Prevention mode when rules must be enforced.
- **Avoid locking yourself out.** Include your current IP address, and retain the jumpbox or Bastion path as a WAF-bypassing safety route.

## Tooling and Repository Hygiene

- **Dotfiles and dotfolders may not survive downloads.** Files such as `.gitignore` and directories such as `.github/` can be filtered. A `github-workflows/` shuttle directory was used as a workaround.
- **Do not manage the same environment with both Bicep and Terraform.** They use different state and naming suffixes, such as `uniqueString` versus SHA-1. Choose one deployment engine per environment.
- **Terraform requires `terraform.tfvars`, not only `terraform.tfvars.example`.** Set `agent_stack_deployed = true` for redeployments. After running `terraform init`, commit `.terraform.lock.hcl`; it was explicitly removed from `.gitignore` for this purpose.
- **Use AzureRM provider version `>= 4.56`.** This is the minimum version needed for the `managedEnvironments` Private Link `target_type`.
- **Account for soft-deleted resources during clean redeployments.** Key Vault and the Foundry Cognitive Services account retain their names after resource-group deletion. Purge them or use a new resource-group name for a clean deployment.

## Operational Reminders

- **Cost:** Fabric F4, Premium ACR, Bastion Standard, NAT Gateway, and Front Door Premium accrue charges continuously. Pause Fabric when idle and roll back Front Door after short demonstrations.
- **Jumpbox image:** Use `2022-datacenter-g2`, not the Azure Edition image. The latter can deactivate itself with a `not running on Azure` message.
- **RDP over Bastion:** The native client command, `az network bastion rdp`, is more stable than a browser session. It requires tunneling to be enabled on the Standard SKU.
