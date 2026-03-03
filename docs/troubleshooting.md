# Troubleshooting Guide

This guide covers common issues encountered when working with this Terraform Azure platform. Each issue follows the format: **Symptom -> Cause -> Solution -> Prevention**.

**Project context:**
- Terraform >= 1.6.0, AzureRM `~> 4.0`, AzureAD `~> 3.0`
- Azure Blob backend (`rg-terraform-state` / `tfstate` container), per-environment state files, blob lease locking
- Azure DevOps CI/CD with OIDC (Workload Identity Federation)
- 14 modules: naming, resource-group, virtual-network, subnet, network-security-group, private-endpoint, key-vault, storage-account, managed-identity, rbac-assignment, log-analytics, aks-cluster, azure-policy, fabric-capacity
- Pre-commit hooks: `terraform_fmt`, `terraform_validate`, `terraform_tflint`, `terraform_docs`, plus standard hooks
- Make targets: `make init`, `make plan`, `make apply`, `make lint`, `make validate`, `make test`

---

## Table of Contents

1. [Authentication Failures](#1-authentication-failures)
2. [State Locking Issues](#2-state-locking-issues)
3. [Provider Version Conflicts](#3-provider-version-conflicts)
4. [Module Dependency Errors](#4-module-dependency-errors)
5. [AzureRM API Errors (Quota, Throttling, Permissions)](#5-azurerm-api-errors-quota-throttling-permissions)
6. [Terraform Plan/Apply Failures](#6-terraform-planapply-failures)
7. [Pre-commit Hook Failures](#7-pre-commit-hook-failures)
8. [CI/CD Pipeline Failures](#8-cicd-pipeline-failures)
9. [Network Connectivity Issues](#9-network-connectivity-issues)
10. [Key Vault Access Denied Errors](#10-key-vault-access-denied-errors)
11. [AKS Cluster Issues](#11-aks-cluster-issues)
12. [Naming Collision Errors](#12-naming-collision-errors)
13. [Import Failures](#13-import-failures)
14. [Terraform State Corruption](#14-terraform-state-corruption)

---

## 1. Authentication Failures

### 1.1 Azure CLI: Not logged in or wrong subscription

**Symptom**
```
Error: building AzureRM Client: obtain subscription() from Azure CLI: parsing json
Error: Error building ARM Config: please ensure you have installed Azure CLI version 2.0.79+
Error: subscription_id is a required provider attribute
```

**Cause**
The local Azure CLI session is unauthenticated, expired, or targeting a different subscription than the one specified in `var.subscription_id`.

**Solution**
```bash
# Authenticate
az login

# Verify the active subscription
az account show --query "{name:name, id:id, state:state}"

# Switch to the correct subscription
az account set --subscription "<subscription-id>"

# Confirm the provider variable is set
grep subscription_id environments/dev/dev.tfvars
```

If using a service principal locally for testing:
```bash
export ARM_CLIENT_ID="<app-id>"
export ARM_CLIENT_SECRET="<secret>"
export ARM_TENANT_ID="<tenant-id>"
export ARM_SUBSCRIPTION_ID="<subscription-id>"
```

**Prevention**
- Set `subscription_id` explicitly in each environment's `.tfvars` file rather than relying on the CLI default.
- Add a Makefile check that validates `az account show` before running `plan` or `apply`.

---

### 1.2 OIDC token exchange failure (CI/CD)

**Symptom**
```
Error: building AzureRM Client: obtain OIDC token: the OIDC token could not be retrieved
AADSTS70021: No matching federated identity record found for presented assertion
AADSTS700213: No matching federated identity record found with issuer
```

**Cause**
The Workload Identity Federation (OIDC) federated credential in Entra ID does not match the subject claim issued by Azure DevOps. This project uses `use_oidc = true` in `backend.tf` and relies on `ARM_USE_OIDC=true` in the pipeline. A mismatch between the configured subject (`sc://<org>/<project>/<service-connection>`) and the token's `sub` claim causes the exchange to fail.

**Solution**
1. Open Entra ID > App Registrations > your service principal > Certificates & secrets > Federated credentials.
2. Verify the subject exactly matches the Azure DevOps service connection subject:
   ```
   sc://<organization>/<project>/<service-connection-name>
   ```
3. Verify the issuer is `https://app.vstoken.visualstudio.com` (or your ADO org URL for newer connections).
4. In the Azure DevOps pipeline, ensure the environment variables are set:
   ```yaml
   env:
     ARM_USE_OIDC: "true"
     ARM_CLIENT_ID: $(servicePrincipalId)
     ARM_TENANT_ID: $(tenantId)
     ARM_SUBSCRIPTION_ID: $(subscriptionId)
   ```
5. Check that the service connection is granted the `AzureCLI@2` or `TerraformTaskV4` task scope needed to request OIDC tokens (`allowScriptToAccessOAuthToken: true`).

**Prevention**
- Document the exact federated credential subject string for each environment's service connection in `docs/adr/006-cicd-auth.md`.
- Use a standardised service connection naming convention so subjects are predictable.
- Add a pipeline step that prints `ARM_CLIENT_ID` and `ARM_TENANT_ID` (not secrets) before Terraform runs to aid debugging.

---

### 1.3 Service principal missing role on subscription or state backend

**Symptom**
```
Error: authorization.RoleAssignmentsClient#Create: Failure: StatusCode=403
Error: Error building ARM Client: Retrieving permissions for Subscription "<id>": authorization: StatusCode=403
```
Or the pipeline succeeds authentication but immediately fails to read the state blob.

**Cause**
The service principal or managed identity used by Terraform lacks the required RBAC roles: `Contributor` (or a custom role) on the subscription, and at minimum `Storage Blob Data Contributor` on the `rg-terraform-state` storage account for state operations.

**Solution**
```bash
# Assign Contributor on the subscription
az role assignment create \
  --assignee "<service-principal-client-id>" \
  --role "Contributor" \
  --scope "/subscriptions/<subscription-id>"

# Assign Storage Blob Data Contributor on the state storage account
az role assignment create \
  --assignee "<service-principal-client-id>" \
  --role "Storage Blob Data Contributor" \
  --scope "/subscriptions/<id>/resourceGroups/rg-terraform-state/providers/Microsoft.Storage/storageAccounts/<sa-name>"
```

**Prevention**
- Codify required role assignments for the CI service principal in a bootstrap checklist or script alongside `scripts/bootstrap-state-backend.sh`.
- Verify role propagation (can take up to 10 minutes in Azure) before the first pipeline run.

---

## 2. State Locking Issues

### 2.1 Stuck blob lease lock

**Symptom**
```
Error: Error locking state: Error acquiring the state lock: storage: service returned error:
StatusCode=409, ErrorCode=LeaseAlreadyPresent, ErrorMessage=There is already a lease present.
Lock Info:
  ID:        <uuid>
  Path:      tfstate/dev.terraform.tfstate
  Operation: OperationTypeApply
  Who:       <user>@<host>
  Created:   <timestamp>
```

**Cause**
A previous `terraform apply` or `terraform plan` was interrupted (pipeline cancelled, process killed, network drop) before Terraform could release the blob lease. Azure blob leases have an infinite duration when acquired by the AzureRM backend.

**Solution**
First confirm no legitimate operation is in progress:
```bash
# Check active pipeline runs in Azure DevOps before proceeding
# Then break the lease via Azure CLI
az storage blob lease break \
  --blob-name "dev.terraform.tfstate" \
  --container-name "tfstate" \
  --account-name "<storage-account-name>" \
  --auth-mode login
```

Alternatively, use Terraform's force-unlock (requires the Lock ID from the error output):
```bash
cd environments/dev
terraform force-unlock <lock-id>
```

**Prevention**
- Enable pipeline cancellation hooks that attempt a clean `terraform force-unlock` before agent shutdown.
- Never cancel a pipeline mid-apply without checking the lock state first.
- The state storage account has a `CanNotDelete` resource lock (applied by `scripts/bootstrap-state-backend.sh`); this protects the backend but does not affect lease management.

---

### 2.2 Concurrent operations across environments sharing state backend

**Symptom**
One environment's apply fails with a lock error even though no operation is actively running against that environment.

**Cause**
This project uses per-environment state files (`dev.terraform.tfstate`, `staging.terraform.tfstate`, `prod.terraform.tfstate`), so environments lock independently. If you see cross-environment locking, either:
- A pipeline is accidentally using the wrong `key` value in `backend.tf`.
- A manual `terraform init` was run with a different backend configuration and the lock is on the wrong blob.

**Solution**
```bash
# Verify the blob key in use matches the environment
grep key environments/dev/backend.tf
# Expected: key = "dev.terraform.tfstate"

# List all blobs and check for unexpected leases
az storage blob list \
  --container-name "tfstate" \
  --account-name "<storage-account-name>" \
  --auth-mode login \
  --query "[].{name:name, leaseState:properties.leaseState}" \
  --output table
```

**Prevention**
- The `environments/shared/backend.tf.tmpl` template enforces `key = "${environment}.terraform.tfstate"`. Always generate `backend.tf` from this template when adding environments.
- CI pipelines should validate `ENV` variable matches the backend key before running init.

---

## 3. Provider Version Conflicts

### 3.1 Lock file version mismatch

**Symptom**
```
Error: Failed to query available provider packages
Error: Inconsistent dependency lock file
  The following dependency selections recorded in the lock file are not consistent with the current configuration
```
Or on `terraform init`:
```
- Installed hashicorp/azurerm v4.x.y (signed by HashiCorp)
  Warning: the lock file is missing the following checksums for hashicorp/azurerm
```

**Cause**
The `.terraform.lock.hcl` file records exact provider versions and checksums. Running `terraform init` on a different OS/architecture than the one that last updated the lock file, or changing version constraints in `providers.tf`, causes a mismatch.

**Solution**
```bash
# Upgrade the lock file for all required platforms
cd environments/dev
terraform init -upgrade

# If you need to support multiple platforms (local + CI Linux):
terraform providers lock \
  -platform=linux_amd64 \
  -platform=darwin_amd64 \
  -platform=darwin_arm64
```

Commit the updated `.terraform.lock.hcl`:
```bash
git add environments/dev/.terraform.lock.hcl
git commit -m "chore: update provider lock file for linux_amd64"
```

**Prevention**
- Commit `.terraform.lock.hcl` to version control (it is not in `.gitignore`).
- Run `terraform providers lock` with all required platforms when updating provider versions.
- CI should run `terraform init` with `-backend=false` during lint/validate stages so lock file discrepancies are caught early.

---

### 3.2 AzureRM 3.x vs 4.x attribute naming conflict

**Symptom**
```
Error: Unsupported argument
  An argument named "enable_rbac_authorization" is not expected here.
Error: Unsupported argument
  An argument named "enable_soft_delete" is not expected here.
```

**Cause**
AzureRM 4.x renamed boolean attributes from `enable_*` to `*_enabled` (e.g., `enable_rbac_authorization` -> `enable_rbac_authorization` is retained in some resources but removed in others). Community modules or copy-pasted examples may use 3.x-style attributes.

**Solution**
Consult the [AzureRM 3.x to 4.x upgrade guide](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/guides/4.0-upgrade-guide) for the specific resource. For this project the known mappings are:

| Resource | 3.x attribute | 4.x attribute |
|---|---|---|
| `azurerm_kubernetes_cluster` | `enable_auto_scaling` | `auto_scaling_enabled` |
| `azurerm_kubernetes_cluster` | `enable_node_public_ip` | `node_public_ip_enabled` |
| `azurerm_kubernetes_cluster_node_pool` | `enable_auto_scaling` | `auto_scaling_enabled` |
| `azurerm_storage_account` | `enable_https_traffic_only` | `https_traffic_only_enabled` |
| `azurerm_key_vault` | `enable_rbac_authorization` | `enable_rbac_authorization` (unchanged) |

```bash
# Use tflint to catch deprecated attributes before apply
make lint
```

**Prevention**
- The `tflint` azurerm ruleset (version `0.27.0` in `.tflint.hcl`) flags deprecated attributes. Run `make lint` before committing.
- Pre-commit hook `terraform_tflint` catches these in the commit workflow.

---

### 3.3 AzureAD provider version conflict with AzureRM

**Symptom**
```
Error: Provider configuration not present
  To work with azuread_... its original provider configuration at provider["registry.terraform.io/hashicorp/azuread"] is required
```
Or unexpected authentication failures when both providers are active.

**Cause**
AzureAD `~> 3.0` (used in this project) and AzureRM `~> 4.0` use separate authentication contexts. If `provider "azuread" {}` is declared without explicit credentials, it inherits from the environment; a mismatch in tenant configuration between the two providers causes failures.

**Solution**
```bash
# Ensure both providers share the same tenant
export ARM_TENANT_ID="<tenant-id>"

# For local work, verify both providers authenticate to the same tenant
az account show --query tenantId
```

In `environments/dev/providers.tf`, the `provider "azuread" {}` block deliberately omits `tenant_id` so it inherits from the environment. Ensure `ARM_TENANT_ID` is exported when running locally.

**Prevention**
- Keep AzureAD and AzureRM versions pinned together in `providers.tf` and test upgrades together.
- When upgrading either provider, check the compatibility matrix in the respective changelogs.

---

## 4. Module Dependency Errors

### 4.1 Module output referenced before resource creation

**Symptom**
```
Error: Reference to undeclared module
  A managed resource "module.foundation_vnet" has not been declared in the root module.
Error: Unsupported attribute
  This object does not have an attribute named "vnet_id".
```

**Cause**
`environments/dev/main.tf` references module outputs (e.g., `module.foundation_vnet.vnet_id`) before the corresponding module block is uncommented and deployed. The phase-based rollout in `main.tf` (Phase 1: Foundation, Phase 2: Identity, etc.) requires modules to be added in dependency order.

**Solution**
Follow the phase ordering when uncommenting module blocks:
1. Phase 1 first: `naming` (already active), `resource_group`, `virtual_network`, `key_vault`, `log_analytics`
2. Phase 2: `managed_identity`, `rbac_assignment`
3. Phase 3 onwards: resources that depend on Phase 1 and 2 outputs

When adding a new module, ensure all referenced outputs exist:
```bash
# Check what a module exports before referencing its outputs
grep -r "^output" modules/virtual-network/outputs.tf
```

**Prevention**
- Add modules incrementally and run `make plan` after each addition before committing.
- Use `depends_on` explicitly where implicit dependencies are not sufficient (e.g., policy assignments that must exist before resource creation).

---

### 4.2 Circular dependency between modules

**Symptom**
```
Error: Cycle: module.aks_cluster, module.rbac_assignment, module.managed_identity
```

**Cause**
Module A references an output of module B, while module B also references an output of module A, creating a cycle Terraform cannot resolve.

**Cause (common pattern)**
The `rbac-assignment` module assigns a role to the AKS cluster's managed identity, but the AKS cluster module references the identity created by the `managed-identity` module, which in turn needs a scope defined by a resource the AKS cluster creates.

**Solution**
Break the cycle by separating concerns:
1. Create the `managed_identity` module first in a separate step.
2. Pass the identity ID into the `aks_cluster` module.
3. Create the `rbac_assignment` module referencing the AKS cluster output and the identity.

```hcl
# Correct ordering - no cycle
module "managed_identity" { ... }

module "aks_cluster" {
  user_assigned_identity_id = module.managed_identity.principal_id
}

module "rbac_assignment" {
  principal_id = module.managed_identity.principal_id
  scope        = module.aks_cluster.node_resource_group_id
}
```

**Prevention**
- Draw a dependency graph before wiring modules: `terraform graph | dot -Tsvg > graph.svg`
- Keep identity creation, resource creation, and role assignment as separate module calls rather than embedding them.

---

## 5. AzureRM API Errors (Quota, Throttling, Permissions)

### 5.1 Subscription quota exceeded

**Symptom**
```
Error: creating Kubernetes Cluster: Code="QuotaExceeded"
  Message="Operation could not be completed as it results in exceeding approved standardDSv3Family Cores quota"
Error: creating Virtual Machine: Code="OperationNotAllowed"
  Message="Operation results in exceeding quota limit of cores"
```

**Cause**
The Azure subscription has insufficient vCPU quota for the requested VM family or region.

**Solution**
```bash
# Check current quota usage for a VM family in a region
az vm list-usage --location eastus2 --output table | grep -i "DSv3\|standard"

# Request a quota increase via the Azure Portal:
# Portal > Subscriptions > <sub> > Usage + quotas > Request increase
```

For AKS specifically, check both the subscription quota and the AKS node pool constraints in `modules/aks-cluster/variables.tf`:
```bash
# Review node pool sizing
grep -A5 "default_node_pool" environments/dev/dev.tfvars
```

**Prevention**
- Request quota increases in non-prod environments before production deployments.
- Use `make cost` (Infracost) to estimate resource requirements early.
- Document required quota per environment in the environment's `README` or `dev.tfvars` comments.

---

### 5.2 API throttling (429 Too Many Requests)

**Symptom**
```
Error: creating/updating Resource Group: azure.BearerAuthorizer#WithAuthorization:
  Failed to refresh the Token for request: StatusCode=429
Error: retryable error: StatusCode=429, ErrorCode=TooManyRequests
```

**Cause**
Azure Resource Manager enforces per-subscription rate limits. Large `terraform apply` runs that create many resources simultaneously can exceed these limits (typically 1200 read requests per hour, 1200 write requests per hour per subscription).

**Solution**
```bash
# Reduce parallelism to slow down API calls
terraform apply -parallelism=5 -var-file=dev.tfvars tfplan

# If already in a throttled state, wait for the rate limit window to reset (typically 1 hour)
# Retry with reduced parallelism
```

**Prevention**
- Default Terraform parallelism is 10. For large applies, set `-parallelism=5` in CI pipeline task configuration.
- Break large applies into phased modules (as the `main.tf` phase comments suggest) to spread API calls across multiple pipeline runs.
- Avoid running `plan` and `apply` in the same short window across multiple environments.

---

### 5.3 Missing resource provider registration

**Symptom**
```
Error: creating Kubernetes Cluster: Code="MissingSubscriptionRegistration"
  Message="The subscription is not registered to use namespace 'Microsoft.ContainerService'"
Error: Code="MissingSubscriptionRegistration"
  Message="The subscription is not registered to use namespace 'Microsoft.Fabric'"
```

**Cause**
Azure resource providers must be registered before their resources can be created. New subscriptions do not have all providers registered by default.

**Solution**
```bash
# Register the required providers
az provider register --namespace Microsoft.ContainerService
az provider register --namespace Microsoft.Fabric
az provider register --namespace Microsoft.KeyVault
az provider register --namespace Microsoft.Storage
az provider register --namespace Microsoft.Network

# Verify registration status (state should become "Registered" within a few minutes)
az provider show --namespace Microsoft.ContainerService --query "registrationState"
```

**Prevention**
- Add a provider registration step to `scripts/bootstrap-state-backend.sh` or a separate bootstrap script.
- Document required provider namespaces per module in each module's `README.md`.

---

## 6. Terraform Plan/Apply Failures

### 6.1 `terraform init` fails to reach backend

**Symptom**
```
Error: Failed to get existing workspaces: storage: service returned error:
  StatusCode=403, ErrorCode=AuthorizationFailure
Error: Error loading state: storage: service returned error: StatusCode=403
```

**Cause**
The identity running `terraform init` lacks `Storage Blob Data Reader` (at minimum) on the state storage account, or the storage account firewall is blocking access.

**Solution**
```bash
# Verify the storage account firewall rules
az storage account show \
  --name "<storage-account-name>" \
  --resource-group "rg-terraform-state" \
  --query "networkRuleSet"

# Temporarily allow your IP if firewall is enabled
az storage account network-rule add \
  --account-name "<storage-account-name>" \
  --resource-group "rg-terraform-state" \
  --ip-address "<your-public-ip>"

# Verify role assignment
az role assignment list \
  --assignee "<your-object-id>" \
  --scope "/subscriptions/<id>/resourceGroups/rg-terraform-state/providers/Microsoft.Storage/storageAccounts/<sa-name>" \
  --query "[].roleDefinitionName"
```

**Prevention**
- Configure the state storage account to allow Azure services and trusted Microsoft services (already configured in `bootstrap-state-backend.sh` via `--https-only true`).
- Grant `Storage Blob Data Contributor` to all identities that need to run Terraform (see Section 1.3).

---

### 6.2 Plan succeeds but apply fails with "already exists"

**Symptom**
```
Error: A resource with the ID "..." already exists - to manage this resource you need to import it into the State
Error: creating Key Vault: Code="VaultAlreadyExists"
```

**Cause**
A resource was created outside of Terraform (manually in the portal, via an old script, or by a previous destroyed-and-recreated run) and is not tracked in state. Terraform plans to create it, then fails when it finds it already exists.

**Solution**
Import the existing resource into state (see also Section 13: Import Failures):
```bash
cd environments/dev

# Example: import an existing Key Vault
terraform import \
  -var-file=dev.tfvars \
  module.foundation_kv.azurerm_key_vault.this \
  "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/<name>"
```

Alternatively, use the import examples in `migration/examples/`:
```bash
cd migration/examples/storage-import
terraform init
terraform import -var-file=variables.tf ...
```

**Prevention**
- Run `make drift` after manual portal changes to detect divergence before the next planned apply.
- Use resource locks (`CanNotDelete`) on critical resources to prevent accidental out-of-band creation/modification.

---

### 6.3 `prevent_deletion_if_contains_resources` blocking resource group destroy

**Symptom**
```
Error: deleting Resource Group "/subscriptions/.../resourceGroups/...":
  Code="ResourceGroupHasResources"
  Message="Resource group cannot be deleted as it contains resources."
```

**Cause**
The `provider "azurerm"` block in `environments/dev/providers.tf` sets `prevent_deletion_if_contains_resources = true` for the `resource_group` feature. This is intentional to prevent accidental destruction of non-empty resource groups.

**Solution**
For legitimate destroy operations:
1. First destroy all child resources within the resource group.
2. Then destroy the resource group itself.

Or, temporarily override in a targeted destroy:
```bash
terraform destroy \
  -target=module.foundation_kv \
  -target=module.foundation_vnet \
  -var-file=dev.tfvars
# Then destroy the resource group
terraform destroy -target=module.foundation_rg -var-file=dev.tfvars
```

**Prevention**
- This behaviour is intentional (see `providers.tf`). Document the ordered destroy sequence for each environment.
- Never set `prevent_deletion_if_contains_resources = false` in production environments.

---

### 6.4 Soft-deleted Key Vault blocking recreation

**Symptom**
```
Error: A soft-deleted Key Vault with the name "..." already exists.
  Please recover the Key Vault or purge it before creating a new one with the same name.
```

**Cause**
Azure Key Vault has a soft-delete retention period (`soft_delete_retention_days`, default 90 days). After destroying a Key Vault via Terraform, the name is reserved for the retention period. The `providers.tf` sets `purge_soft_delete_on_destroy = false`, which means Terraform will not automatically purge on destroy.

**Solution**
```bash
# List soft-deleted Key Vaults
az keyvault list-deleted --query "[].{name:name, id:id}"

# Recover the existing Key Vault (preferred)
az keyvault recover --name "<vault-name>"

# Or purge it permanently (irreversible — requires Purge permissions)
az keyvault purge --name "<vault-name>" --location "<location>"
```

After recovery, re-import the recovered vault into state:
```bash
terraform import \
  -var-file=dev.tfvars \
  module.foundation_kv.azurerm_key_vault.this \
  "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/<name>"
```

**Prevention**
- The naming module generates Key Vault names up to 24 characters using `{project}-{env}-{location_short}-kv`. Use unique `suffix` values per deployment to avoid name collisions after destroy.
- In non-production environments where rapid iteration is needed, consider setting `soft_delete_retention_days = 7` (minimum) to shorten the reservation window.
- Document the Key Vault name for each environment so the recover/purge decision is informed.

---

## 7. Pre-commit Hook Failures

### 7.1 `terraform_fmt` fails

**Symptom**
```
terraform_fmt...........................................................Failed
- hook id: terraform_fmt
- exit code: 1
  main.tf
```

**Cause**
One or more `.tf` files do not match the canonical Terraform formatting style enforced by `terraform fmt`.

**Solution**
```bash
# Auto-fix formatting across all files
make fmt
# Or directly:
terraform fmt -recursive

# Then stage and re-commit
git add -u
git commit
```

**Prevention**
- Configure your editor to run `terraform fmt` on save (VS Code: HashiCorp Terraform extension with `editor.formatOnSave`).
- The pre-commit hook catches this before commits reach CI.

---

### 7.2 `terraform_validate` fails

**Symptom**
```
terraform_validate......................................................Failed
- hook id: terraform_validate
- exit code: 1
  Error: Reference to undeclared input variable
    on main.tf line 5, in resource "azurerm_resource_group" "this":
    var.undefined_var
```

**Cause**
A variable is referenced but not declared, a resource attribute is invalid, or a module call is missing a required argument.

**Solution**
```bash
# Run validate directly in the failing environment
cd environments/dev && terraform init -backend=false && terraform validate

# For modules, validate in the module directory
cd modules/key-vault && terraform init -backend=false && terraform validate
```

**Prevention**
- Run `make validate ENV=dev` after any structural change.
- Keep `versions.tf` files in each module up to date so `terraform init -backend=false` succeeds without remote backend credentials.

---

### 7.3 `terraform_tflint` fails

**Symptom**
```
terraform_tflint........................................................Failed
- hook id: terraform_tflint
  Error: `terraform_documented_variables` rule: variable "my_var" is not documented (missing description)
  Error: `terraform_naming_convention` rule: variable name "myVar" must match snake_case
  Error: `terraform_typed_variables` rule: variable "my_var" does not have a type
```

**Cause**
TFLint rules defined in `.tflint.hcl` are violated. This project enforces:
- `terraform_naming_convention`: snake_case for all resource labels and variable names
- `terraform_documented_variables`: all variables must have a `description`
- `terraform_documented_outputs`: all outputs must have a `description`
- `terraform_typed_variables`: all variables must declare a `type`
- AzureRM ruleset: deprecated attributes and invalid argument values

**Solution**
```bash
# Run tflint and see all violations
make lint
# Or directly:
tflint --config=.tflint.hcl --recursive

# Fix each violation:
# - Add description = "..." to variables and outputs
# - Add type = string/number/bool/list/map/object to variables
# - Rename camelCase labels to snake_case
# - Replace deprecated AzureRM 3.x attributes with 4.x equivalents
```

**Prevention**
- Use the module scaffolding pattern from existing modules (e.g., `modules/key-vault/variables.tf`) as a template when creating new modules — all variables include `description` and `type`.
- Run `make lint` as part of local development before opening a PR.

---

### 7.4 `terraform_docs` fails or generates unexpected diff

**Symptom**
```
terraform_docs..........................................................Failed
- hook id: terraform_docs
  Files were modified by this hook: modules/key-vault/README.md
```

**Cause**
The `README.md` in a module is out of date with the current variable/output/resource definitions. The `terraform_docs` hook regenerates the README and fails if it had to make changes (indicating the committed README was stale).

**Solution**
```bash
# Regenerate all module READMEs
make docs
# Or for a specific module:
terraform-docs markdown table --output-file README.md --output-mode inject modules/key-vault/

# Stage and re-commit the updated READMEs
git add modules/*/README.md
git commit
```

**Prevention**
- Always run `make docs` after modifying module variables or outputs before committing.
- The pre-commit hook will auto-update and fail the commit; simply re-stage and commit again.

---

### 7.5 `detect-private-key` false positive or genuine detection

**Symptom**
```
detect-private-key......................................................Failed
- hook id: detect-private-key
  modules/key-vault/examples/basic/main.tf
```

**Cause**
A file contains a string that matches the private key pattern (`-----BEGIN ... PRIVATE KEY-----`). This may be a genuine private key accidentally staged, or a false positive in a test fixture or example file.

**Solution**
```bash
# Identify the offending file and line
grep -rn "PRIVATE KEY" modules/key-vault/examples/

# If it is a false positive (test fixture, documentation example):
# Add the file to .pre-commit-config.yaml exclude list for this hook:
# - id: detect-private-key
#   exclude: "modules/.*/examples/.*"

# If it is a genuine key: remove it immediately, rotate the key, and audit git history
git log --all --full-history -- path/to/file
```

**Prevention**
- Never put real credentials in example files or test fixtures.
- Use placeholder values like `"<private-key-pem>"` in examples.

---

## 8. CI/CD Pipeline Failures

### 8.1 Pipeline cannot find Terraform binary

**Symptom**
```
/bin/bash: terraform: command not found
##[error]Bash exited with code '127'.
```

**Cause**
The Azure DevOps pipeline agent does not have Terraform installed, or the `TerraformInstaller@1` task has not run before the Terraform task.

**Solution**
Add a Terraform installer task before any Terraform commands in the pipeline YAML:
```yaml
- task: TerraformInstaller@1
  displayName: 'Install Terraform'
  inputs:
    terraformVersion: '1.6.x'  # Must satisfy >= 1.6.0
```

Or use the `TerraformTaskV4` task which handles installation automatically.

**Prevention**
- Pin the Terraform version in the pipeline to match `required_version = ">= 1.6.0"` in `providers.tf`.
- Use a self-hosted agent with Terraform pre-installed for faster pipeline execution.

---

### 8.2 Pipeline fails with wrong working directory

**Symptom**
```
Error: No configuration files
##[error]terraform plan: exit status 1
```

**Cause**
The pipeline task is running `terraform plan` from the repository root instead of the environment directory. The Makefile targets handle this via `cd $(ENV_DIR)`, but direct pipeline commands may not.

**Solution**
```yaml
# Option 1: Use the Makefile targets
- script: make init plan ENV=dev
  displayName: 'Terraform Plan (dev)'

# Option 2: Set working directory explicitly
- task: TerraformTaskV4@4
  inputs:
    command: 'plan'
    workingDirectory: '$(System.DefaultWorkingDirectory)/environments/dev'
    commandOptions: '-var-file=dev.tfvars -out=tfplan'
```

**Prevention**
- Standardise all pipeline Terraform operations through Makefile targets (`make init`, `make plan`, `make apply`) to ensure correct working directory.

---

### 8.3 Stale `tfplan` file used in apply

**Symptom**
```
Error: Saved plan is stale
  The given plan file can no longer be applied because the state was changed by another operation after the plan was created.
```

**Cause**
The `tfplan` artifact from the plan stage is used in the apply stage, but between plan and apply, either:
- Another pipeline run applied changes to the same environment's state.
- The plan file was not passed as a pipeline artifact and Terraform is trying to apply an older cached file.

**Solution**
```yaml
# In the plan stage, publish tfplan as an artifact
- publish: environments/dev/tfplan
  artifact: tfplan-dev

# In the apply stage, download the artifact
- download: current
  artifact: tfplan-dev
  targetPath: environments/dev/

# Then apply
- script: make apply ENV=dev
```

**Prevention**
- Always pass the plan file as a pipeline artifact between stages.
- Add a pipeline approval gate before the apply stage to prevent concurrent applies.
- Use environment-level pipeline locks in Azure DevOps to serialise deployments per environment.

---

## 9. Network Connectivity Issues

### 9.1 Private endpoint DNS resolution failing

**Symptom**
Resources deployed behind private endpoints (Key Vault, Storage Account) are unreachable from within the VNet, or Terraform itself cannot reach them during plan/apply:
```
Error: Error making Read request on Azure Key Vault
  dial tcp: lookup <vault-name>.vault.azure.net: no such host
```
Or application-level errors:
```
Failed to connect to <storage-account>.blob.core.windows.net: Name or service not known
```

**Cause**
The `modules/private-endpoint` module creates a private endpoint and optionally registers a `private_dns_zone_group` (when `var.private_dns_zone_ids` is non-empty). If the private DNS zone group is not configured, or the private DNS zone is not linked to the VNet, Azure DNS will continue resolving the resource to its public IP rather than the private endpoint IP.

**Solution**
```bash
# Verify the private endpoint has a DNS zone group
az network private-endpoint show \
  --name "<pe-name>" \
  --resource-group "<rg>" \
  --query "privateDnsZoneGroups"

# Verify the private DNS zone is linked to the VNet
az network private-dns link vnet list \
  --resource-group "<rg>" \
  --zone-name "privatelink.vaultcore.azure.net" \
  --query "[].{name:name, vnetId:virtualNetwork.id, registrationEnabled:registrationEnabled}"

# Verify DNS resolution from within the VNet (run from a VM inside the VNet)
nslookup <vault-name>.vault.azure.net
# Should resolve to 10.x.x.x (private IP), not 52.x.x.x (public IP)
```

Ensure `var.private_dns_zone_ids` is populated when calling the `private-endpoint` module:
```hcl
module "kv_private_endpoint" {
  source = "../../modules/private-endpoint"
  # ...
  private_dns_zone_ids = [azurerm_private_dns_zone.keyvault.id]  # Must not be empty
}
```

**Prevention**
- Always pass `private_dns_zone_ids` when deploying private endpoints. The module's `private_dns_zone_group` block is conditional on this list being non-empty — an empty list silently skips DNS registration.
- Test DNS resolution from a VM in the target subnet immediately after deploying private endpoints.

---

### 9.2 NSG rules blocking expected traffic

**Symptom**
Resources are deployed successfully but traffic between subnets is blocked. Common manifestation: AKS nodes cannot reach the API server, or services cannot reach Key Vault via private endpoint.

**Cause**
The `modules/network-security-group` module applies NSG rules to subnets. Default-deny rules or incorrectly ordered rules (NSGs evaluate by priority, lowest number wins) may block legitimate traffic.

**Solution**
```bash
# Check effective NSG rules on a NIC or subnet
az network nic show-effective-nsg \
  --name "<nic-name>" \
  --resource-group "<rg>" \
  --query "effectiveNetworkSecurityGroups[].effectiveSecurityRules[]" \
  --output table

# Check NSG flow logs (if enabled via Log Analytics)
# Navigate to: Network Watcher > Flow logs > <nsg-name>

# Test connectivity with Network Watcher
az network watcher test-connectivity \
  --source-resource "<vm-id>" \
  --dest-address "<private-endpoint-ip>" \
  --dest-port 443
```

Verify that AKS-required NSG rules are in place:
- Allow TCP 443 outbound to `AzureCloud` (API server)
- Allow TCP 443 inbound/outbound for the AKS subnet to the private endpoint subnet
- Allow `AzureLoadBalancer` inbound (priority <= 65001)

**Prevention**
- Review NSG rules in `modules/network-security-group/variables.tf` and document required rules for each subnet type (AKS, private-endpoint, general).
- Enable NSG flow logs via the Log Analytics workspace deployed by the `log-analytics` module.

---

## 10. Key Vault Access Denied Errors

### 10.1 403 on Key Vault data-plane operations

**Symptom**
```
Error: checking for presence of existing Secret "my-secret" (Key Vault "https://<vault>.vault.azure.net"):
  keyvault.BaseClient#GetSecret: Failure responding to request:
  StatusCode=403 -- Original Error: autorest/azure: Service returned an error.
  Status=403 Code="Forbidden" Message="The user, group or application does not have secrets get permission on key vault"
```

**Cause**
This project's Key Vault module uses `enable_rbac_authorization = true`. With RBAC authorization enabled, Access Policies are ignored — access is controlled exclusively through Azure RBAC role assignments. The identity making the request lacks a Key Vault data-plane RBAC role (`Key Vault Secrets User`, `Key Vault Secrets Officer`, `Key Vault Administrator`).

**Solution**
```bash
# Check current role assignments on the Key Vault
az role assignment list \
  --scope "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/<vault>" \
  --query "[].{principal:principalName, role:roleDefinitionName}" \
  --output table

# Assign the appropriate role
az role assignment create \
  --assignee "<object-id>" \
  --role "Key Vault Secrets User" \
  --scope "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/<vault>"
```

Use the `rbac-assignment` module to manage this through Terraform:
```hcl
module "kv_secret_access" {
  source = "../../modules/rbac-assignment"

  principal_id         = module.managed_identity.principal_id
  role_definition_name = "Key Vault Secrets User"
  scope                = module.foundation_kv.key_vault_id
}
```

**Prevention**
- Manage all Key Vault access through the `rbac-assignment` module — never add access policies manually in the portal.
- Include Key Vault role assignments in the same Terraform apply as the resources that need them, using `depends_on` if needed to sequence them correctly.
- Remember that RBAC role propagation can take 2-10 minutes in Azure; add retry logic in applications reading from Key Vault at startup.

---

### 10.2 Key Vault firewall blocking Terraform or CI/CD

**Symptom**
```
Error: Error making Read request on Azure Key Vault Secret
  StatusCode=403 Reason="Forbidden"
  Message="Client address is not authorized and caller is not a trusted service."
```

**Cause**
The Key Vault module's `network_acls` block sets `default_action = var.network_acls_default_action` (deny by default in hardened configurations). The IP address of the runner or the CI/CD agent is not in `var.network_acls_ip_rules` and the VNet subnet is not in `var.network_acls_virtual_network_subnet_ids`.

**Solution**
```bash
# Check Key Vault network ACLs
az keyvault show \
  --name "<vault-name>" \
  --query "properties.networkAcls" \
  --output json

# Add the CI agent's outbound IP to the allowed list
az keyvault network-rule add \
  --name "<vault-name>" \
  --ip-address "<agent-outbound-ip>/32"

# Or, if using a self-hosted agent in the VNet, add the subnet:
az keyvault network-rule add \
  --name "<vault-name>" \
  --vnet-name "<vnet-name>" \
  --subnet "<subnet-name>"
```

The `network_acls` block in `modules/key-vault/main.tf` always sets `bypass = "AzureServices"`, which permits Terraform operations when running from Azure-hosted CI agents.

**Prevention**
- Use self-hosted Azure DevOps agents running inside the project VNet for all Terraform operations against network-restricted Key Vaults.
- Pass `network_acls_ip_rules` as a variable in each environment's `.tfvars` to authorise developer workstation IPs during development.

---

## 11. AKS Cluster Issues

### 11.1 Node not ready

**Symptom**
```
kubectl get nodes
NAME                                STATUS     ROLES    AGE
aks-default-12345678-vmss000000     NotReady   agent    5m
```

**Cause**
Common causes after a Terraform apply:
- Node pool VM extension installation in progress (transient — wait 5-10 minutes after cluster creation).
- CNI plugin failure: `azure` CNI overlay mode (`network_plugin_mode = "overlay"`) misconfiguration or IP exhaustion in the pod CIDR.
- Insufficient node pool capacity in the selected `zones` (AZ capacity constraint).
- Azure Policy add-on (`azure_policy_enabled = true`) failing to initialize.

**Solution**
```bash
# Check node conditions
kubectl describe node <node-name> | grep -A20 "Conditions:"

# Check system pod status
kubectl get pods -n kube-system

# Check AKS diagnostics
az aks show \
  --name "<cluster-name>" \
  --resource-group "<rg>" \
  --query "agentPoolProfiles[].{name:name, powerState:powerState, provisioningState:provisioningState}"

# Review AKS diagnostics logs in Log Analytics (if OMS agent is enabled)
# KubeNodeInventory | where TimeGenerated > ago(1h) | where Status != "Ready"
```

For CNI overlay issues, verify `service_cidr` and `dns_service_ip` in `modules/aks-cluster/main.tf` do not overlap with the VNet address space:
```hcl
network_profile {
  network_plugin      = "azure"
  network_plugin_mode = "overlay"
  service_cidr        = "172.16.0.0/16"   # Must not overlap with VNet
  dns_service_ip      = "172.16.0.10"
}
```

**Prevention**
- Define non-overlapping CIDRs for VNet, service CIDR, and pod CIDR before deployment.
- Use availability zones (`zones = ["1", "2", "3"]`) in `default_node_pool` for HA, but verify AZ capacity for the chosen VM SKU first.
- Monitor cluster health via the Log Analytics diagnostic settings configured by the `aks-cluster` module (`kube-apiserver`, `kube-audit-admin`, `guard` log categories).

---

### 11.2 Pod scheduling failures

**Symptom**
```
kubectl get pods
NAME        READY   STATUS    RESTARTS   AGE
my-app      0/1     Pending   0          10m

kubectl describe pod my-app
  Warning  FailedScheduling  Insufficient cpu (3)
  Warning  FailedScheduling  0/2 nodes are available: 2 node(s) had taint {CriticalAddonsOnly: true}
```

**Cause**
Two distinct causes are common in this cluster configuration:

1. **Taint on system node pool**: The `default_node_pool` can be configured with `only_critical_addons_enabled = true`, which taints nodes with `CriticalAddonsOnly`. User workload pods without the corresponding toleration will not schedule on these nodes.
2. **Resource limits exceeded**: Autoscaler has not yet scaled out, or `min_count`/`max_count` bounds prevent scale-out.

**Solution**
For taint issue — deploy user workloads to a dedicated user node pool:
```hcl
# In the aks_cluster module call, add a user node pool
additional_node_pools = {
  user = {
    vm_size    = "Standard_D4s_v3"
    min_count  = 1
    max_count  = 5
    mode       = "User"        # Not "System"
    node_taints = []           # No CriticalAddonsOnly taint
    # ...
  }
}
```

For autoscaler — check current node counts and bounds:
```bash
az aks nodepool show \
  --cluster-name "<cluster-name>" \
  --resource-group "<rg>" \
  --name "default" \
  --query "{min:minCount, max:maxCount, current:count, provisioningState:provisioningState}"
```

**Prevention**
- Always configure at least one `User` mode node pool for application workloads when `only_critical_addons_enabled = true` on the system pool.
- Set `max_count` high enough in `additional_node_pools` to accommodate peak load.
- Review `max_pods` per node (default varies by CNI mode) to ensure adequate pod density.

---

## 12. Naming Collision Errors

### 12.1 Storage account name already taken globally

**Symptom**
```
Error: creating Storage Account: Code="StorageAccountAlreadyTaken"
  Message="The storage account named 'stplatformdeveus2abc123' is already taken."
```

**Cause**
Storage account names are globally unique across all Azure tenants. The `modules/naming` module generates storage names as:
```
{project}{environment}{location_short}st{unique_hash}
```
where `unique_hash = substr(sha256(var.unique_seed), 0, 6)`. If `unique_seed` (set to `var.subscription_id` in `environments/dev/main.tf`) produces a hash that collides with an existing account in another tenant, creation fails.

**Solution**
```bash
# Check if the name is available
az storage account check-name --name "<storage-account-name>" --query "nameAvailable"

# If taken, change the unique_seed to produce a different hash
# In environments/dev/main.tf:
module "naming" {
  source      = "../../modules/naming"
  project     = var.project
  environment = var.environment
  location    = var.location
  unique_seed = "${var.subscription_id}-v2"  # Append a suffix to change the hash
}
```

**Prevention**
- Always use `var.subscription_id` (or a derivative) as `unique_seed` since subscription IDs are unique per tenant.
- Collisions are extremely rare with a 6-character hex hash (16.7M combinations), but if they occur, appending a version suffix to the seed resolves them deterministically.

---

### 12.2 Key Vault name exceeds 24 characters or already exists

**Symptom**
```
Error: creating Key Vault: Code="VaultNameNotValid"
  Message="Vault name must be between 3-24 alphanumeric characters and hyphens, beginning with a letter."
Error: A soft-deleted Key Vault already exists with the name "..."
```

**Cause**
The naming module caps Key Vault names at 24 characters with `substr(...)`. If the base name is close to 24 characters and a `suffix` is provided, the truncation may produce an invalid name (e.g., ending with a hyphen) or conflict with a soft-deleted vault.

**Solution**
```bash
# Check the generated Key Vault name
terraform console -var-file=dev.tfvars
> module.naming.outputs.key_vault_name

# If truncation is causing issues, shorten the project or suffix:
# modules/naming/main.tf applies substr to cap at 24 chars
# Verify the generated name ends with an alphanumeric character
```

For soft-delete conflicts, see Section 6.4.

**Prevention**
- Keep `var.project` short (4-8 characters) to leave room for env/location abbreviations and the `-kv` suffix within the 24-character limit.
- The naming module outputs should be reviewed after any change to `project`, `environment`, or `suffix` values.

---

## 13. Import Failures

### 13.1 Import ID format incorrect

**Symptom**
```
Error: Cannot import non-existent remote object
  While attempting to import an existing object to "module.foundation_rg.azurerm_resource_group.this",
  the provider detected that no object exists with the given id.
  The provider API reported:
  StatusCode=404
```
Or:
```
Error: Invalid provider resource identifier format
```

**Cause**
Azure resource IDs are case-sensitive in specific segments and must include the full path. Common mistakes include wrong resource type casing, missing resource group segment, or an ID copied from the portal that uses a different format.

**Solution**
```bash
# Get the exact resource ID from Azure CLI (authoritative format)
az resource show \
  --name "<resource-name>" \
  --resource-group "<rg-name>" \
  --resource-type "Microsoft.Network/virtualNetworks" \
  --query "id" \
  --output tsv

# Use the import helper script for common resource types
bash scripts/import-helper.sh

# Then import using the exact ID
cd environments/dev
terraform import \
  -var-file=dev.tfvars \
  module.foundation_vnet.azurerm_virtual_network.this \
  "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<name>"
```

Reference the `migration/examples/` directory for tested import patterns:
- `migration/examples/storage-import/` — Storage Account import
- `migration/examples/network-import/` — VNet/subnet import

**Prevention**
- Always retrieve resource IDs via `az resource show ... --query id` rather than constructing them manually.
- Use `scripts/import-helper.sh` which encapsulates correct ID format construction.
- After import, immediately run `terraform plan` to confirm zero diff before making changes.

---

### 13.2 Import creates a diff on next plan

**Symptom**
After a successful `terraform import`, the next `terraform plan` shows unexpected changes:
```
  ~ resource "azurerm_key_vault" "this" {
      ~ soft_delete_retention_days = 90 -> 7
      ~ purge_protection_enabled   = true -> false
    }
```

**Cause**
The imported resource's actual configuration in Azure differs from what is declared in Terraform. This is common when importing resources that were created manually with different settings than the module defaults.

**Solution**
Decide whether to:
1. **Adopt the existing configuration** — update the Terraform code to match the imported resource's actual values to produce a zero-diff plan.
2. **Converge to desired state** — accept the diff and apply it to bring the resource into compliance with the module defaults.

```bash
# Inspect the current resource state after import
terraform state show module.foundation_kv.azurerm_key_vault.this

# Compare with what Azure reports
az keyvault show --name "<vault-name>" --query "properties"
```

**Prevention**
- Before importing, audit the existing resource's configuration and align the Terraform declaration with it.
- Run `terraform plan` immediately after every import before making any further changes.
- Document imported resources and their pre-import state in a migration log.

---

## 14. Terraform State Corruption

### 14.1 State file is empty or truncated

**Symptom**
```
Error: Failed to load state: state file has no content
Error: Failed to parse state: unexpected end of JSON
```

**Cause**
A failed write to the Azure Blob backend (network interruption, process kill during write) can leave the state file empty or truncated. The blob versioning enabled by `scripts/bootstrap-state-backend.sh` (`--enable-versioning true`) retains previous versions for recovery.

**Solution**
```bash
# List blob versions to find the last good state
az storage blob list \
  --container-name "tfstate" \
  --account-name "<storage-account-name>" \
  --include "v" \
  --query "[?name=='dev.terraform.tfstate'].{versionId:versionId, lastModified:properties.lastModified, contentLength:properties.contentLength}" \
  --auth-mode login \
  --output table

# Download a specific version to inspect it
az storage blob download \
  --container-name "tfstate" \
  --name "dev.terraform.tfstate" \
  --version-id "<version-id>" \
  --file "dev.terraform.tfstate.backup" \
  --account-name "<storage-account-name>" \
  --auth-mode login

# Verify the backup is valid JSON
python3 -m json.tool dev.terraform.tfstate.backup > /dev/null && echo "Valid JSON"

# Restore by uploading the valid version as the current blob
az storage blob upload \
  --container-name "tfstate" \
  --name "dev.terraform.tfstate" \
  --file "dev.terraform.tfstate.backup" \
  --account-name "<storage-account-name>" \
  --auth-mode login \
  --overwrite
```

**Prevention**
- Blob versioning (30-day retention) and soft delete are enabled by `scripts/bootstrap-state-backend.sh`. Never disable these settings on the state storage account.
- The `CanNotDelete` resource lock on `rg-terraform-state` prevents accidental deletion of the storage account or container.
- Take a manual backup of state before destructive operations:
  ```bash
  terraform state pull > state-backup-$(date +%Y%m%d-%H%M%S).json
  ```

---

### 14.2 Resource in state but not in Azure (dangling state entry)

**Symptom**
```
Error: deleting Resource Group: Code="ResourceGroupNotFound"
  Message="Resource group 'rg-platform-dev-eus2' could not be found."
```
Or `terraform plan` shows resources that no longer exist in Azure as needing to be destroyed.

**Cause**
A resource was deleted directly in the Azure Portal or via `az` CLI without going through Terraform, leaving a stale reference in state.

**Solution**
```bash
# Remove the dangling resource from state without destroying anything in Azure
terraform state rm module.foundation_rg.azurerm_resource_group.this

# Or for multiple resources, use a targeted refresh to detect all drifts
terraform apply -refresh-only -var-file=dev.tfvars
```

After removing from state, run `make plan` to confirm no unexpected changes remain.

**Prevention**
- Enforce a policy that all Azure resource changes go through Terraform. Use Azure Policy (managed by the `azure-policy` module) to audit or deny manual resource creation in managed resource groups.
- Run `make drift` regularly to detect state divergence before it causes apply failures.
- Use the `CanNotDelete` resource lock on critical resource groups to prevent accidental portal deletion.

---

### 14.3 State contains sensitive values exposed in logs

**Symptom**
CI/CD pipeline logs show secrets (connection strings, keys) that were stored in Terraform state and emitted during a `terraform show` or verbose logging.

**Cause**
Terraform state stores all resource attributes, including sensitive ones. Running `terraform show` or enabling `TF_LOG=DEBUG` can expose these values in CI logs.

**Solution**
```bash
# Mark sensitive outputs to suppress them in plan/apply output
output "storage_primary_connection_string" {
  value     = module.storage_account.primary_connection_string
  sensitive = true  # Prevents display in plan/apply output
}
```

Audit pipeline log retention settings and mask sensitive variables in Azure DevOps:
- Azure DevOps > Pipeline > Variables > mark secret variables as secret (padlock icon).

**Prevention**
- Never set `TF_LOG=DEBUG` or `TF_LOG=TRACE` in CI pipelines that log to a shared artifact store.
- Mark all outputs containing connection strings, keys, and passwords as `sensitive = true` in module `outputs.tf` files.
- Use Key Vault references instead of passing secrets directly as Terraform variable values.

---

## Quick Reference: Diagnostic Commands

```bash
# Authentication
az account show
az account list --output table

# State backend
az storage blob list --container-name tfstate --account-name <sa> --auth-mode login --output table
az storage blob lease show --blob-name dev.terraform.tfstate --container-name tfstate --account-name <sa> --auth-mode login

# Terraform operations
make init ENV=dev
make validate ENV=dev
make lint
make plan ENV=dev
make drift ENV=dev

# Lock management
terraform force-unlock <lock-id>

# State inspection
terraform state list
terraform state show <resource-address>
terraform state pull > state-backup.json

# Provider/module diagnostics
terraform providers
terraform graph | dot -Tsvg > graph.svg
TF_LOG=INFO terraform plan -var-file=dev.tfvars 2>&1 | head -100

# AKS
kubectl get nodes
kubectl get pods -A
kubectl describe node <node>
az aks show --name <cluster> --resource-group <rg>

# Key Vault
az keyvault show --name <vault>
az keyvault list-deleted
az role assignment list --scope <vault-id> --query "[].{principal:principalName, role:roleDefinitionName}"

# Network
az network private-endpoint show --name <pe> --resource-group <rg>
az network nic show-effective-nsg --name <nic> --resource-group <rg>
```

---

## Related Documentation

- `docs/adr/001-provider-version.md` — AzureRM 4.x decision and upgrade notes
- `docs/adr/003-state-management.md` — State backend design and environment isolation
- `docs/adr/004-naming-convention.md` — Naming pattern and collision handling
- `docs/adr/006-cicd-auth.md` — OIDC authentication setup and federated credential configuration
- `docs/adr/007-aks-feature-profile.md` — AKS feature decisions
- `scripts/bootstrap-state-backend.sh` — State backend provisioning
- `scripts/import-helper.sh` — Resource import utilities
- `migration/examples/` — Tested import patterns for common resource types
- `Makefile` — All available make targets (`make help`)
