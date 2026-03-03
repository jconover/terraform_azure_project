# Disaster Recovery Runbook

**Service:** Azure Infrastructure (terraform_azure_project)
**Owner:** Platform Engineering
**Last Updated:** 2026-03-03
**Review Cycle:** Quarterly

---

## Table of Contents

1. [DR Overview and RPO/RTO Targets](#1-dr-overview-and-rpoto-targets)
2. [Backup Inventory](#2-backup-inventory)
3. [Scenario 1: Complete Environment Loss](#3-scenario-1-complete-environment-loss)
4. [Scenario 2: AKS Cluster Failure](#4-scenario-2-aks-cluster-failure)
5. [Scenario 3: Key Vault Disaster](#5-scenario-3-key-vault-disaster)
6. [Scenario 4: Storage Account Data Loss](#6-scenario-4-storage-account-data-loss)
7. [Scenario 5: State Backend Loss](#7-scenario-5-state-backend-loss)
8. [Scenario 6: CI/CD Pipeline Compromise](#8-scenario-6-cicd-pipeline-compromise)
9. [Scenario 7: Region Failure](#9-scenario-7-region-failure)
10. [DR Testing Schedule and Procedures](#10-dr-testing-schedule-and-procedures)
11. [Communication Plan](#11-communication-plan)
12. [Post-Incident Review Template](#12-post-incident-review-template)
13. [DR Automation Opportunities](#13-dr-automation-opportunities)

---

## 1. DR Overview and RPO/RTO Targets

### Architecture Summary

This project provisions Azure infrastructure across three environments (dev, staging, prod) using 14 Terraform modules in a monorepo. Core resources per environment:

| Resource | Module | Notes |
|---|---|---|
| AKS Cluster | `modules/aks-cluster` | Azure CNI Overlay, autoscaler, OIDC issuer |
| Storage Accounts | `modules/storage-account` | Soft delete 30d, versioning enabled |
| Key Vault | `modules/key-vault` | Purge protection, soft delete 90d, RBAC auth |
| Virtual Network | `modules/virtual-network` | 10.0.0.0/16, private endpoints |
| Log Analytics | `modules/log-analytics` | All resources emit diagnostics |
| Terraform State | Azure Blob Storage | `rg-terraform-state` / `stterraformstate` / container `tfstate` |

All changes are delivered exclusively via Azure DevOps CI/CD using OIDC (Workload Identity Federation). No manual portal changes are permitted per the immutable infrastructure principle.

### RPO/RTO Targets

| Environment | RPO | RTO | Justification |
|---|---|---|---|
| prod | 1 hour | 4 hours | Business-critical workloads; state versioned, IaC complete |
| staging | 4 hours | 8 hours | Pre-production validation; acceptable longer recovery |
| dev | 24 hours | 24 hours | Development only; full rebuild from Terraform is acceptable |

**RPO** (Recovery Point Objective): Maximum acceptable data loss measured in time.
**RTO** (Recovery Time Objective): Maximum acceptable time to restore service.

These targets assume:
- Terraform state is recoverable (soft delete 30 days, versioning enabled).
- Key Vault secrets are within the 90-day soft delete retention window.
- The monorepo is intact and accessible.
- At least one operator with Owner/Contributor rights on the subscription is available.

---

## 2. Backup Inventory

### What Is Backed Up and How

| Asset | Backup Mechanism | Retention | Recovery Method |
|---|---|---|---|
| Terraform state (`dev.terraform.tfstate`) | Azure Blob versioning + soft delete | 30 days for deleted blobs; all prior versions indefinitely until deleted | Restore prior blob version or undelete soft-deleted blob |
| Terraform state (`staging.terraform.tfstate`) | Same as above | Same as above | Same as above |
| Terraform state (`prod.terraform.tfstate`) | Same as above | Same as above | Same as above |
| Key Vault secrets/keys/certs | Key Vault soft delete | 90 days (configurable 7–90d, default 90d in module) | Recover from soft-deleted state; purge protection prevents permanent deletion during window |
| Key Vault vault itself | Soft delete + purge protection | 90 days | Recover deleted vault via Azure CLI/portal |
| AKS cluster configuration | Terraform IaC (source of truth) | Git history (indefinite) | Re-apply Terraform; no Azure-native backup of cluster config |
| AKS workload state | Application team responsibility | Per application SLA | Application-level backup (Velero recommended, out of scope for this runbook) |
| Virtual Network / NSG config | Terraform IaC (source of truth) | Git history (indefinite) | Re-apply Terraform |
| Log Analytics workspace data | Azure Monitor retention policy | Default 30 days (configurable) | Data is observability; loss does not affect service availability |
| Azure DevOps pipelines | Azure DevOps (YAML in monorepo) | Git history (indefinite) | Re-import from `pipelines/` directory |
| OIDC federated credentials (Entra ID) | Terraform IaC or manual documentation | Git history | Re-create service principal + federated credentials per ADR-006 |
| Resource group + subscription config | Terraform IaC | Git history (indefinite) | Re-apply Terraform |

### What Is NOT Backed Up (Explicit Gaps)

- **AKS persistent volume data**: Application-level concern; Velero or equivalent required per workload.
- **Log Analytics historical data beyond retention**: Logs are observability; extend retention if compliance requires archival.
- **Azure DevOps variable groups with secrets**: Rotate and re-enter if lost; do not store irreplaceable secrets here.
- **Customer-managed encryption keys (CMK)** beyond Key Vault soft delete: Permanent key deletion permanently destroys data encrypted with that key.

---

## 3. Scenario 1: Complete Environment Loss

**Trigger:** An entire environment's resource group is deleted, subscription is compromised, or infrastructure is irrecoverably corrupted.

**Estimated Recovery Time:** 2–4 hours (prod), 1–2 hours (dev/staging)

### Prerequisites

- Access to the monorepo (Git remote must be accessible).
- Azure subscription with Contributor or Owner rights.
- Azure DevOps service connection with OIDC federated credentials intact, OR ability to re-create them.
- Terraform state recoverable (see Scenario 5 if state is also lost).

### Step-by-Step Recovery

**Step 1: Assess scope of loss**

Determine which resources are gone and whether Terraform state is intact:

```bash
# Verify state storage account is alive
az storage account show \
  --name stterraformstate \
  --resource-group rg-terraform-state

# List state blobs
az storage blob list \
  --account-name stterraformstate \
  --container-name tfstate \
  --auth-mode login \
  --output table
```

If state is also missing, complete Scenario 5 first, then return here.

**Step 2: Verify CI/CD pipeline access**

Confirm the Azure DevOps service connection for the affected environment is functional:

```
Azure DevOps > Project Settings > Service connections
> [env]-azure-service-connection > Verify
```

If the service connection is broken, re-create the federated credential in Entra ID and update the service connection. Refer to ADR-006 for the OIDC setup procedure.

**Step 3: Run Terraform plan to assess drift**

Trigger the plan pipeline for the affected environment from a clean branch:

```
Azure DevOps > Pipelines > [env]-plan
> Run pipeline > Select main branch
```

Review the plan output carefully. All resources in the resource group will show as `to be created`. Verify the plan matches expectations before proceeding.

**Step 4: Apply in dependency order**

The module dependency graph (from ARCHITECTURE.md) defines the correct apply order. Terraform handles this automatically when applying from the environment root. Trigger the apply pipeline:

```
Azure DevOps > Pipelines > [env]-apply
> Run pipeline (staging/prod: await manual approval gate)
```

Apply sequence (handled automatically by Terraform):
1. `naming` (no dependencies)
2. `resource-group`, `common-tags`
3. `virtual-network`, `log-analytics`, `managed-identity`
4. `subnet`
5. `nsg`, `private-endpoint`
6. `key-vault`, `storage-account`
7. `aks-cluster`
8. `rbac-assignment`

**Step 5: Restore secrets to Key Vault**

After Key Vault is recreated, secrets must be restored. If the original Key Vault was soft-deleted (within 90 days), recover it first (see Scenario 3). Otherwise, secrets must be re-entered by the secret owners. Do not store the canonical secret values only in Azure DevOps variable groups.

**Step 6: Validate environment health**

```bash
# AKS cluster reachable
az aks get-credentials \
  --resource-group <rg-name> \
  --name <aks-name> \
  --overwrite-existing

kubectl get nodes
kubectl get pods --all-namespaces

# Key Vault accessible
az keyvault secret list --vault-name <kv-name>

# Log Analytics workspace receiving data
az monitor log-analytics query \
  --workspace <workspace-id> \
  --analytics-query "Heartbeat | summarize count() by bin(TimeGenerated, 5m) | take 5"
```

**Step 7: Notify stakeholders**

Follow the Communication Plan in Section 11. Update incident status from "recovering" to "restored".

---

## 4. Scenario 2: AKS Cluster Failure

**Trigger:** AKS cluster is in a failed state, node pools are unhealthy, the control plane is unreachable, or a failed upgrade has left the cluster non-functional.

**Estimated Recovery Time:** 30 minutes (node pool recycle) to 2 hours (full cluster replacement)

### Triage Decision Tree

```
AKS cluster unreachable
        |
        v
Is the control plane API server responding?
    No  --> Azure platform incident? Check https://status.azure.com
    Yes --> Are node pools healthy?
                No  --> Attempt node pool recycle (Step A)
               Yes  --> Application-level issue (out of scope)
```

### Step A: Recycle Unhealthy Node Pool

If node pools are in a bad state but the control plane is alive:

```bash
# Check node pool status
az aks nodepool list \
  --cluster-name <aks-name> \
  --resource-group <rg-name> \
  --output table

# Scale node pool to 0, then back to desired count
az aks nodepool scale \
  --cluster-name <aks-name> \
  --resource-group <rg-name> \
  --name <nodepool-name> \
  --node-count 0

az aks nodepool scale \
  --cluster-name <aks-name> \
  --resource-group <rg-name> \
  --name <nodepool-name> \
  --node-count <desired-count>
```

If autoscaler is enabled (`auto_scaling_enabled = true` in the module), verify min/max bounds are not constraining the scale operation.

### Step B: Replace the AKS Cluster via Terraform

When the cluster must be replaced entirely:

**Step B1: Taint the AKS cluster resource in state**

```bash
cd environments/<env>

terraform init \
  -backend-config="resource_group_name=rg-terraform-state" \
  -backend-config="storage_account_name=stterraformstate" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=<env>.terraform.tfstate" \
  -backend-config="use_oidc=true"

terraform taint 'module.<aks_module_name>.azurerm_kubernetes_cluster.this'
```

**Step B2: Run plan to confirm only AKS is replaced**

```bash
terraform plan -out=aks-recovery.tfplan
```

Review the plan. Only the AKS cluster and its diagnostic setting should show as `to be replaced`. If dependent resources (node pools, RBAC assignments) also appear, verify they are expected.

**Step B3: Apply via pipeline**

Commit the taint to a recovery branch and trigger the apply pipeline, or run locally with appropriate OIDC credentials:

```bash
terraform apply aks-recovery.tfplan
```

**Step B4: Retrieve updated kubeconfig**

```bash
az aks get-credentials \
  --resource-group <rg-name> \
  --name <aks-name> \
  --overwrite-existing

kubectl get nodes
```

**Step B5: Restore workloads**

AKS cluster replacement destroys all running workloads. Application teams must redeploy from their GitOps repositories (Flux/Argo CD as noted in ADR-007 as out-of-scope for this module but expected as the deployment mechanism). Coordinate with application teams for workload restoration.

### AKS-Specific Diagnostics

The AKS module emits the following diagnostic logs to Log Analytics (configured in `modules/aks-cluster/main.tf`):

- `kube-apiserver`: API server logs
- `kube-audit-admin`: Admin audit trail
- `guard`: Entra ID authentication events

Query Log Analytics for pre-failure context:

```kusto
AzureDiagnostics
| where ResourceType == "MANAGEDCLUSTERS"
| where TimeGenerated > ago(2h)
| where Level == "Error" or Level == "Warning"
| project TimeGenerated, Category, log_s
| order by TimeGenerated desc
```

---

## 5. Scenario 3: Key Vault Disaster

**Trigger:** Key Vault is accidentally deleted, secrets are deleted, or the vault is in a corrupted/inaccessible state.

**Estimated Recovery Time:** 15–30 minutes (vault recovery from soft delete), 2–4 hours (secret re-entry if not in soft delete)

### Key Vault Protection Configuration

As defined in `modules/key-vault/variables.tf`:

- `purge_protection_enabled = true` (default): Prevents permanent deletion during retention window. The vault **cannot** be permanently destroyed for 90 days after deletion.
- `soft_delete_retention_days = 90` (default): Deleted vault and all its objects are recoverable for 90 days.
- `enable_rbac_authorization = true` (default): Access is controlled via Azure RBAC, not legacy access policies.
- `public_network_access_enabled = false` (default): Vault is private; access requires being on the VNet or via private endpoint.

### Recovery: Deleted Vault (Within 90-Day Window)

```bash
# List soft-deleted vaults
az keyvault list-deleted --output table

# Recover the vault
az keyvault recover --name <vault-name> --location <region>

# Verify recovery
az keyvault show --name <vault-name>
```

After vault recovery, all secrets, keys, and certificates that were present at deletion time are automatically restored in their soft-deleted state. Recover each object:

```bash
# List soft-deleted secrets
az keyvault secret list-deleted --vault-name <vault-name>

# Recover each secret
az keyvault secret recover \
  --vault-name <vault-name> \
  --name <secret-name>

# List soft-deleted keys
az keyvault key list-deleted --vault-name <vault-name>

# Recover each key
az keyvault key recover \
  --vault-name <vault-name> \
  --name <key-name>
```

### Recovery: Vault Permanently Purged (After Retention Window or Forced Purge)

Because `purge_protection_enabled = true`, a forced purge is not possible during the retention window. After 90 days, data is irrecoverably lost. Response:

1. Re-create the Key Vault via Terraform (run `terraform apply` for the environment).
2. Retrieve secret values from secondary sources (application teams' secure documentation, HSMs, upstream secret providers).
3. Re-enter secrets manually or via a secret seeding script.
4. Rotate all credentials that were stored in the vault as a precaution.
5. Audit who had access to secrets using Key Vault audit logs in Log Analytics before they expired.

### Recovery: Individual Secrets Deleted (Vault Intact)

```bash
# List deleted secrets
az keyvault secret list-deleted \
  --vault-name <vault-name> \
  --output table

# Recover specific secret
az keyvault secret recover \
  --vault-name <vault-name> \
  --name <secret-name>

# Verify
az keyvault secret show \
  --vault-name <vault-name> \
  --name <secret-name>
```

### Recovery: RBAC Access Lost

If the RBAC assignments granting access to Key Vault are lost (e.g., Managed Identity deleted):

```bash
# Re-apply Terraform to restore rbac-assignment module resources
# The rbac-assignment module codifies all access grants
cd environments/<env>
terraform plan  # verify RBAC assignments show as to be created
terraform apply
```

### Audit Query: Who Accessed Key Vault Before the Incident

```kusto
AzureDiagnostics
| where ResourceType == "VAULTS"
| where TimeGenerated > ago(7d)
| where ResultType != "Success" or OperationName contains "Delete"
| project TimeGenerated, OperationName, ResultType, CallerIPAddress, identity_claim_http_schemas_xmlsoap_org_ws_2005_05_identity_claims_upn_s
| order by TimeGenerated desc
```

---

## 6. Scenario 4: Storage Account Data Loss

**Trigger:** Blobs are accidentally deleted, overwritten, or a storage container is dropped.

**Estimated Recovery Time:** 15 minutes (soft delete recovery), 30–60 minutes (version restore)

### Storage Protection Configuration

As defined in `modules/storage-account/variables.tf`:

- `blob_soft_delete_retention_days = 30` (default): Deleted blobs are recoverable for 30 days.
- `container_soft_delete_retention_days = 30` (default): Deleted containers are recoverable for 30 days.
- `versioning_enabled = true` (default): All blob writes create a new version; prior versions are accessible.
- `shared_access_key_enabled = false` (default): SAS key access disabled; RBAC-only access reduces blast radius of credential compromise.
- `public_network_access_enabled = false` (default): Private network access only.

### Recovery: Soft-Deleted Blobs

```bash
# List soft-deleted blobs in a container
az storage blob list \
  --account-name <storage-account-name> \
  --container-name <container-name> \
  --include d \
  --auth-mode login \
  --output table

# Undelete a specific blob
az storage blob undelete \
  --account-name <storage-account-name> \
  --container-name <container-name> \
  --name <blob-name> \
  --auth-mode login
```

### Recovery: Soft-Deleted Container

```bash
# List soft-deleted containers
az storage container list \
  --account-name <storage-account-name> \
  --include-deleted \
  --auth-mode login \
  --output table

# Restore soft-deleted container
az storage container restore \
  --account-name <storage-account-name> \
  --name <container-name> \
  --deleted-version <version-id> \
  --auth-mode login
```

### Recovery: Restore a Prior Blob Version

```bash
# List all versions of a blob
az storage blob list \
  --account-name <storage-account-name> \
  --container-name <container-name> \
  --include v \
  --prefix <blob-name> \
  --auth-mode login \
  --output table

# Copy a prior version to the current version
az storage blob copy start \
  --account-name <storage-account-name> \
  --destination-container <container-name> \
  --destination-blob <blob-name> \
  --source-account-name <storage-account-name> \
  --source-container <container-name> \
  --source-blob <blob-name> \
  --source-version-id <version-id> \
  --auth-mode login
```

### Recovery: Storage Account Itself Deleted

If the storage account resource is deleted (not just blobs), the account is subject to the storage account-level soft delete if configured at the subscription/resource group level (not enabled by default in this module). If not recoverable:

1. Re-create the storage account via `terraform apply`.
2. Restore blob data from application-level backups.
3. If data is irretrievably lost, conduct a data loss assessment and notify affected stakeholders.

### Customer-Managed Key Consideration

If the storage account uses a CMK (`cmk_key_vault_key_id` is set), the Key Vault key must be intact and accessible before the storage account data is recoverable. Always recover Key Vault (Scenario 3) before attempting storage data recovery in CMK configurations.

---

## 7. Scenario 5: State Backend Loss

**Trigger:** The Terraform state storage account (`stterraformstate` in `rg-terraform-state`) is deleted, the state blobs are deleted, or state is corrupted.

**Estimated Recovery Time:** 30 minutes (blob recovery) to 4 hours (state reconstruction)

This is the highest-severity infrastructure scenario because loss of state decouples Terraform from real Azure resources, making subsequent `plan`/`apply` operations destructive.

### State Backend Configuration

From `environments/dev/backend.tf` (identical pattern for staging and prod):

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "stterraformstate"
    container_name       = "tfstate"
    key                  = "dev.terraform.tfstate"   # staging.terraform.tfstate, prod.terraform.tfstate
    use_oidc             = true
  }
}
```

Per ADR-003, the state storage account has:
- Blob soft delete: 30 days
- Blob versioning: enabled
- CanNotDelete resource lock (applied by bootstrap script)

### Step 1: Confirm the Scope of Loss

```bash
# Check if resource group exists
az group show --name rg-terraform-state

# Check if storage account exists
az storage account show \
  --name stterraformstate \
  --resource-group rg-terraform-state

# Check if state blobs exist (including soft-deleted)
az storage blob list \
  --account-name stterraformstate \
  --container-name tfstate \
  --include d \
  --auth-mode login \
  --output table
```

### Step 2: Recover Soft-Deleted State Blob

If the blob was deleted within the 30-day retention window:

```bash
# Undelete the state blob for a specific environment
az storage blob undelete \
  --account-name stterraformstate \
  --container-name tfstate \
  --name <env>.terraform.tfstate \
  --auth-mode login

# Verify
az storage blob show \
  --account-name stterraformstate \
  --container-name tfstate \
  --name <env>.terraform.tfstate \
  --auth-mode login
```

### Step 3: Restore a Prior State Version

If the current state is corrupt but prior versions exist:

```bash
# List versions of the state file
az storage blob list \
  --account-name stterraformstate \
  --container-name tfstate \
  --include v \
  --prefix <env>.terraform.tfstate \
  --auth-mode login \
  --output table

# Restore a specific version (replace <version-id> from list output)
az storage blob copy start \
  --account-name stterraformstate \
  --destination-container tfstate \
  --destination-blob <env>.terraform.tfstate \
  --source-account-name stterraformstate \
  --source-container tfstate \
  --source-blob <env>.terraform.tfstate \
  --source-version-id <version-id> \
  --auth-mode login
```

### Step 4: Reconstruct State from Live Infrastructure

If no blob version is recoverable, state must be reconstructed by importing existing Azure resources into a fresh state file. This is time-consuming but avoids destroying live infrastructure.

```bash
cd environments/<env>

# Initialize with empty/new state
terraform init \
  -backend-config="resource_group_name=rg-terraform-state" \
  -backend-config="storage_account_name=stterraformstate" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=<env>.terraform.tfstate" \
  -backend-config="use_oidc=true"

# Import each resource using its Azure resource ID
# Import order must follow the module dependency graph (ARCHITECTURE.md)

# Example: import resource group
terraform import \
  'module.<rg_module>.azurerm_resource_group.this' \
  '/subscriptions/<sub-id>/resourceGroups/<rg-name>'

# Example: import Key Vault
terraform import \
  'module.<kv_module>.azurerm_key_vault.this' \
  '/subscriptions/<sub-id>/resourceGroups/<rg-name>/providers/Microsoft.KeyVault/vaults/<kv-name>'

# Example: import AKS cluster
terraform import \
  'module.<aks_module>.azurerm_kubernetes_cluster.this' \
  '/subscriptions/<sub-id>/resourceGroups/<rg-name>/providers/Microsoft.ContainerService/managedClusters/<aks-name>'
```

Refer to `migration/examples/` in the monorepo for import patterns used in previous migrations.

After importing all resources, run `terraform plan` and verify the output shows **no changes**. Any diff indicates a mismatch between the imported state and the Terraform configuration that must be resolved before the next apply.

### Step 5: Rebuild the State Backend Itself

If the state storage account resource group is gone and cannot be recovered:

```bash
# Re-run the bootstrap script (creates state storage account outside Terraform)
bash scripts/bootstrap-state-backend.sh

# Then re-initialize and import or rebuild as above
```

### Step 6: Prevent Recurrence

After recovery, verify these safeguards are in place:

```bash
# Confirm CanNotDelete lock on state resource group
az lock list --resource-group rg-terraform-state --output table

# Confirm soft delete is enabled on state storage account
az storage account blob-service-properties show \
  --account-name stterraformstate \
  --resource-group rg-terraform-state \
  --query "deleteRetentionPolicy"

# Confirm versioning is enabled
az storage account blob-service-properties show \
  --account-name stterraformstate \
  --resource-group rg-terraform-state \
  --query "isVersioningEnabled"
```

---

## 8. Scenario 6: CI/CD Pipeline Compromise

**Trigger:** Azure DevOps pipeline is compromised, a malicious pipeline run executes destructive Terraform operations, OIDC service connection credentials are misused, or an unauthorized actor gains pipeline access.

**Estimated Response Time:** Immediate containment (minutes), full investigation 2–8 hours

### Immediate Containment

**Step 1: Disable the compromised service connection**

```
Azure DevOps > Project Settings > Service connections
> [affected-service-connection] > Edit > Disable
```

This immediately prevents any new pipeline runs from authenticating to Azure using the OIDC token.

**Step 2: Revoke federated credentials in Entra ID**

```bash
# Find the service principal used by the service connection
az ad sp list --display-name <service-principal-name> --output table

# Remove all federated credentials from the service principal
az ad app federated-credential list \
  --id <app-id> \
  --output table

# Delete the specific federated credential
az ad app federated-credential delete \
  --id <app-id> \
  --federated-credential-id <credential-id>
```

Because OIDC uses short-lived tokens (no stored secrets per ADR-006), revoking the federated credential immediately invalidates all future token exchanges. In-flight tokens may remain valid for their short TTL (typically 10 minutes).

**Step 3: Lock the Azure subscription or resource group (if active destruction is occurring)**

```bash
# Emergency lock on prod resource group to prevent any further changes
az lock create \
  --name emergency-lock \
  --resource-group <prod-rg-name> \
  --lock-type CanNotDelete
```

For active Terraform destroy operations, also apply a ReadOnly lock:

```bash
az lock create \
  --name emergency-readonly \
  --resource-group <prod-rg-name> \
  --lock-type ReadOnly
```

Note: ReadOnly locks on resource groups will break Terraform operations. Remove them after containment is confirmed.

**Step 4: Identify the blast radius**

```bash
# Review Azure Activity Log for the service principal's actions in the last 24 hours
az monitor activity-log list \
  --caller <service-principal-object-id> \
  --start-time $(date -u -d "24 hours ago" +%Y-%m-%dT%H:%M:%SZ) \
  --output table
```

Query Log Analytics for Key Vault access by the compromised identity:

```kusto
AzureDiagnostics
| where ResourceType == "VAULTS"
| where identity_claim_http_schemas_xmlsoap_org_ws_2005_05_identity_claims_upn_s contains "<sp-name>"
| where TimeGenerated > ago(24h)
| project TimeGenerated, OperationName, ResultType, requestUri_s
| order by TimeGenerated desc
```

**Step 5: Assess and remediate infrastructure damage**

Run `terraform plan` for each environment against the current Azure state to identify what was changed or destroyed. Use recovered Terraform state (Scenario 5 if necessary) to guide remediation. Re-apply to restore desired state.

**Step 6: Rotate all secrets that were accessible**

Any Key Vault secret, key, or certificate that the compromised service principal had access to must be considered exposed. Rotate them:

1. Generate new secret values.
2. Update secrets in Key Vault.
3. Notify application teams to update their workloads.
4. Revoke and re-issue any certificates.

**Step 7: Re-establish CI/CD access**

After the incident is contained and the compromise vector is understood:

1. Create a new service principal with a new object ID.
2. Configure new federated credentials per ADR-006 procedures.
3. Create a new Azure DevOps service connection.
4. Update pipeline YAML to reference the new service connection.
5. Run a test pipeline on a non-production environment before re-enabling prod.

**Step 8: Harden pipeline access controls**

Review and tighten:
- Branch protection rules (restrict which branches can trigger apply pipelines).
- Pipeline approvals and checks (2-approver gate for prod must be intact).
- Service connection scope (restrict to specific resource groups, not entire subscription if possible).
- Azure DevOps project permissions (who can edit pipeline YAML).

---

## 9. Scenario 7: Region Failure

**Trigger:** An Azure region experiences a prolonged outage affecting one or more environments.

**Estimated Recovery Time:** 4–8 hours for prod (cross-region rebuild), dependent on data replication status

### Regional Dependency Assessment

All environments are currently deployed to a single Azure region. Cross-region DR requires a rebuild in an alternate region using Terraform with modified location variables.

### Step 1: Confirm regional failure scope

Check Azure Service Health:
- Portal: https://portal.azure.com/#blade/Microsoft_Azure_Health/AzureHealthBrowseBlade
- Status page: https://status.azure.com
- CLI: `az monitor activity-log list --filters "resourceType eq 'Microsoft.ResourceHealth/availabilityStatuses'" --output table`

Confirm the outage affects services in scope: AKS, Storage, Key Vault, VNet, Log Analytics.

### Step 2: Verify state backend availability

The state backend (`stterraformstate` in `rg-terraform-state`) must be accessible for any Terraform operations. If the state storage account is in the failed region:

- If `account_replication_type` is `GRS` or `RAGRS`, initiate a failover:

```bash
az storage account failover \
  --name stterraformstate \
  --resource-group rg-terraform-state
```

- If the account is `LRS` (local only), the state is unavailable during a regional failure. State reconstruction (Scenario 5, Step 4) will be required after the alternate region environment is provisioned.

### Step 3: Provision infrastructure in the alternate region

Update environment variables to point to the alternate region:

```hcl
# environments/prod/variables.tf override for DR
# Change location from e.g. "eastus" to "westus2"
variable "location" {
  default = "westus2"  # DR target region
}
```

The naming module (`modules/naming`) generates resource names from the `location` variable, so names will differ in the alternate region. This is expected and correct.

Trigger the environment pipeline targeting the DR region, or run locally:

```bash
cd environments/prod

terraform init -reconfigure \
  -backend-config="resource_group_name=rg-terraform-state-dr" \
  -backend-config="storage_account_name=stterraformstatedr" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=prod-dr.terraform.tfstate" \
  -backend-config="use_oidc=true"

terraform plan -var="location=westus2" -out=dr.tfplan
terraform apply dr.tfplan
```

### Step 4: Restore data

- **Key Vault**: If the original vault had geo-redundancy (Premium SKU with geo-replication) or a backup, restore. Otherwise, re-enter secrets from secure documentation.
- **Storage**: If `account_replication_type` was `GRS`/`RAGRS`/`GZRS`/`RAGZRS`, the data is available in the paired region after failover. If `LRS`, data may be lost; restore from application-level backups.
- **AKS workloads**: Redeploy from GitOps repositories. PVC data requires application-level backup (e.g., Velero with cross-region replication).

### Step 5: Update DNS and traffic routing

Update DNS records and any traffic management configuration (Azure Front Door, Traffic Manager, or application-level) to route to the alternate region endpoints. This is application-team responsibility for workload traffic; platform engineering is responsible for infrastructure endpoint updates.

### Step 6: Plan for region restoration

When the primary region recovers:
1. Do not automatically fail back. Validate the primary region's health first.
2. Plan a maintenance window for fail-back.
3. Sync any data written in the DR region back to the primary region before decommissioning DR resources.
4. Re-apply the original environment configuration in the primary region.
5. Clean up DR region resources via `terraform destroy` targeting the DR state file.

---

## 10. DR Testing Schedule and Procedures

### Testing Schedule

| Test Type | Frequency | Scope | Responsible Team |
|---|---|---|---|
| State restore drill | Monthly | Restore a prior state blob version in dev | Platform Engineering |
| Terraform re-apply drill | Quarterly | Destroy and rebuild dev environment from scratch | Platform Engineering |
| Key Vault recovery drill | Quarterly | Soft-delete and recover a test Key Vault in dev | Platform Engineering |
| AKS node pool recycle | Monthly | Drain and recycle a node pool in staging | Platform Engineering |
| Full DR simulation | Bi-annually | Simulate region failure; rebuild prod in alternate region (read-only; no data destruction) | Platform Engineering + App Teams |
| Pipeline compromise simulation | Annually | Revoke and re-establish OIDC credentials; test pipeline recovery | Platform Engineering + Security |
| Runbook review | Quarterly | Walk through each scenario; update procedures | Platform Engineering |

### State Restore Drill Procedure

1. Identify the current state blob version ID:
   ```bash
   az storage blob list \
     --account-name stterraformstate \
     --container-name tfstate \
     --include v \
     --prefix dev.terraform.tfstate \
     --auth-mode login \
     --output table
   ```
2. Copy a 24-hour-old version to a test blob:
   ```bash
   az storage blob copy start \
     --account-name stterraformstate \
     --destination-container tfstate \
     --destination-blob dev.terraform.tfstate.drtest \
     --source-account-name stterraformstate \
     --source-container tfstate \
     --source-blob dev.terraform.tfstate \
     --source-version-id <24h-old-version-id> \
     --auth-mode login
   ```
3. Initialize Terraform against the test blob and run `plan`. Verify plan output reflects the delta between 24h-ago state and current Azure resources.
4. Delete the test blob. Record test results in the incident log.

### Terraform Re-apply Drill Procedure

1. Select the dev environment. Confirm no active development work is in progress.
2. Record the current resource IDs of all dev resources.
3. Run `terraform destroy` in dev via pipeline (with explicit approval gate).
4. Verify all dev resources are deleted.
5. Run `terraform apply` in dev via pipeline.
6. Verify all dev resources are recreated with correct configuration.
7. Record time-to-recovery. Compare against the 24-hour RTO target for dev.
8. Document any manual steps that were required beyond pipeline execution.

### Test Result Documentation

Record all test results in the team's incident management system with:
- Date and participants
- Scenario tested
- Actual time to recovery
- Steps that failed or required unplanned manual intervention
- Action items with owners and due dates

---

## 11. Communication Plan

### Severity Classification

| Severity | Definition | Example |
|---|---|---|
| SEV-1 | Production down or data loss confirmed | AKS cluster unreachable; Key Vault purged |
| SEV-2 | Production degraded or imminent risk | State backend inaccessible; CI/CD pipeline compromised |
| SEV-3 | Non-production environment affected | Dev environment lost; staging pipeline failing |
| SEV-4 | Potential future risk identified | Soft delete expiring soon; lock missing |

### Notification Timeline

| Time | Action | Owner |
|---|---|---|
| T+0 | Incident detected | On-call engineer |
| T+5 min | Incident declared; SEV assigned; war-room created | Incident commander |
| T+15 min | Initial stakeholder notification sent (SEV-1/2) | Incident commander |
| T+30 min | First status update; impact and recovery ETA communicated | Incident commander |
| T+60 min | Hourly status updates until resolved | Incident commander |
| T+recovery | Resolution notification; services restored confirmation | Incident commander |
| T+24h | Preliminary post-incident report distributed | Incident commander |
| T+5 days | Full post-incident review published | Platform Engineering lead |

### Stakeholder Notification Template

**Subject:** [SEV-X] Infrastructure Incident - [Environment] - [Brief Description]

```
Incident: [One-line summary]
Environment: [dev / staging / prod]
Severity: [SEV-1 / SEV-2 / SEV-3 / SEV-4]
Start Time: [UTC timestamp]
Impact: [What is affected and how users are impacted]
Current Status: [Investigating / Identified / Recovering / Resolved]
ETA to Resolution: [Time or "Unknown - investigating"]
Incident Commander: [Name]
War Room: [Link to Teams/Slack channel or bridge]
Next Update: [UTC timestamp]
```

### Escalation Contacts

| Role | Responsibility | Contact Method |
|---|---|---|
| On-call Platform Engineer | First responder; triage and initial response | PagerDuty rotation |
| Platform Engineering Lead | SEV-1/2 escalation; approves destructive recovery actions | Phone / PagerDuty |
| Azure Subscription Owner | Emergency subscription-level actions | Phone |
| Azure Support | Platform-level failures; open a severity A support ticket | Azure portal support |
| Security Team | SEV-1/2 incidents with suspected compromise | Security incident channel |
| Application Team Leads | Workload restoration coordination | Team channel |

### Azure Support Escalation

For platform-level Azure failures (region outage, service degradation):

```
Azure Portal > Help + Support > New support request
> Issue type: Technical
> Service: [Affected service]
> Severity: Critical (Sev A) for production outages
```

Always include:
- Subscription ID
- Affected resource IDs
- Correlation IDs from Azure Activity Log
- Timeline of observed behavior

---

## 12. Post-Incident Review Template

Complete within 5 business days of incident resolution. Share with all stakeholders. Focus on systemic improvement, not individual blame.

---

### Post-Incident Review: [Incident Title]

**Date of Incident:** [YYYY-MM-DD]
**Date of Review:** [YYYY-MM-DD]
**Severity:** [SEV-X]
**Duration:** [HH:MM from detection to resolution]
**Incident Commander:** [Name]
**Participants:** [Names and roles]

---

#### 1. Incident Summary

[2–4 sentence summary of what happened, what the impact was, and how it was resolved.]

---

#### 2. Timeline

| Time (UTC) | Event | Actor |
|---|---|---|
| HH:MM | [Event description] | [Person/System] |
| HH:MM | [Event description] | [Person/System] |

---

#### 3. Root Cause Analysis

**Root Cause:**
[Single clear statement of the underlying cause. Use the "5 Whys" technique if helpful.]

**Contributing Factors:**
- [Factor 1]
- [Factor 2]

---

#### 4. Impact Assessment

| Dimension | Detail |
|---|---|
| User impact | [Who was affected and how] |
| Data impact | [Was any data lost or compromised? How much?] |
| Financial impact | [Estimated cost if known] |
| RPO met? | [Yes / No — actual data loss vs. target] |
| RTO met? | [Yes / No — actual recovery time vs. target] |

---

#### 5. What Went Well

- [Thing 1 — detection was fast, runbook was accurate, etc.]
- [Thing 2]

---

#### 6. What Went Poorly

- [Thing 1 — runbook step was missing, access was unavailable, etc.]
- [Thing 2]

---

#### 7. Action Items

| Action | Owner | Due Date | Priority |
|---|---|---|---|
| [Specific action] | [Name] | [YYYY-MM-DD] | [High/Med/Low] |
| Update this runbook with [section] | [Name] | [YYYY-MM-DD] | High |

---

#### 8. Runbook Gaps Identified

[List any steps in this runbook that were missing, incorrect, or difficult to follow during the incident. Include the section and line so they can be updated immediately.]

---

#### 9. Detection and Alerting Review

**How was the incident detected?**
[Manual discovery / alert / monitoring / user report]

**Was there an earlier signal that was missed?**
[Yes/No — describe]

**Alert improvements needed:**
- [Alert 1 to add or tune]

---

#### 10. Sign-off

| Role | Name | Date |
|---|---|---|
| Incident Commander | | |
| Platform Engineering Lead | | |
| Security (if applicable) | | |

---

## 13. DR Automation Opportunities

The following automation improvements would reduce RTO, reduce human error during incidents, and increase confidence in DR capabilities.

### High Priority

**1. Automated State Backup Verification (Monthly)**

A scheduled pipeline that:
- Lists state blob versions for all three environments.
- Verifies at least N versions exist (ensuring versioning is working).
- Verifies the most recent version is within 24 hours of the last expected apply.
- Alerts via Azure Monitor if any check fails.

Implementation: Azure DevOps scheduled pipeline (`schedules:` trigger) calling the Azure CLI checks in Section 7.

**2. State Integrity Check Pipeline**

A pipeline that runs `terraform plan` in read-only mode against all environments on a schedule and alerts if the plan produces unexpected changes (drift detection). Unexpected drift may indicate manual portal changes or unauthorized modifications.

Implementation: Add a `drift-detection` pipeline to `pipelines/` that runs `terraform plan -detailed-exitcode` and fails the pipeline (triggering an alert) if exitcode is 2 (changes detected).

**3. Key Vault Secret Expiry Alerting**

An Azure Monitor alert rule that fires when Key Vault secrets or certificates approach expiry. This prevents secrets from expiring in production unexpectedly.

Implementation: Key Vault diagnostic logs already flow to Log Analytics. Add an alert rule:

```kusto
AzureDiagnostics
| where ResourceType == "VAULTS"
| where OperationName == "SecretNearExpiry"
```

### Medium Priority

**4. Automated DR Drill Execution**

A pipeline that automates the monthly state restore drill (Section 10). Runs on a schedule, copies a prior state version to a test blob, initializes Terraform against it, captures the plan output, and posts results to a Teams/Slack channel.

**5. Cross-Region State Replication**

Implement a scheduled job to copy state blobs from the primary region storage account to a storage account in the DR region. This reduces dependency on Azure's geo-replication for state recovery in a region failure scenario.

```bash
# Example: replicate state blobs to DR storage account
az storage blob copy start \
  --account-name stterraformstatedr \
  --destination-container tfstate \
  --destination-blob prod.terraform.tfstate.replica \
  --source-account-name stterraformstate \
  --source-container tfstate \
  --source-blob prod.terraform.tfstate \
  --auth-mode login
```

**6. Runbook Validation as Code**

Convert all Azure CLI commands in this runbook to executable scripts in `scripts/dr/`. Each script should be idempotent and include preflight checks (does the target resource exist? is the operator authenticated?). Scripts serve as both automation and tested documentation.

Suggested structure:
```
scripts/dr/
  recover-state-blob.sh          # Scenario 5, Steps 2-3
  recover-keyvault.sh            # Scenario 3
  recover-soft-deleted-blobs.sh  # Scenario 4
  revoke-oidc-credentials.sh     # Scenario 6, Steps 1-2
  validate-environment-health.sh # Post-recovery validation
  dr-drill-state-restore.sh      # Section 10 drill
```

### Lower Priority

**7. Velero Integration for AKS Workload Backup**

Deploy Velero with an Azure Blob Storage backend to provide application-level backup and restore for AKS persistent volumes. This closes the documented gap in the backup inventory (Section 2) and reduces RTO for workload restoration after AKS cluster replacement.

**8. Automated Runbook Updates via CI**

A CI check that validates this runbook's Azure CLI command syntax against the installed `az` CLI version on each PR. Prevents runbook rot as Azure CLI syntax evolves.

**9. Infrastructure Health Dashboard**

An Azure Workbook or Grafana dashboard aggregating:
- AKS node pool health
- Key Vault availability and error rates
- Storage account availability
- Terraform state blob age (time since last apply)
- Azure DevOps pipeline success rates

This provides a single-pane-of-glass view for the on-call engineer during incident triage.

---

*This runbook is a living document. Update it immediately when procedures change, when gaps are identified during incidents (Section 12, item 8), or during quarterly reviews. File updates as PRs to the monorepo so changes are reviewed and tracked in git history.*
