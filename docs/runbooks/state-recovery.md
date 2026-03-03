# Runbook: Terraform State Recovery

**Version:** 1.0
**Last Updated:** 2026-03-03
**Owner:** Platform Engineering
**Applies To:** All environments (dev, staging, prod)
**Related ADR:** [ADR-003: Azure Blob Backend with Per-Environment State](../adr/003-state-management.md)

---

## Table of Contents

1. [Overview of State Architecture](#1-overview-of-state-architecture)
2. [Common State Issues](#2-common-state-issues)
3. [Recovering from Soft-Deleted State](#3-recovering-from-soft-deleted-state)
4. [Recovering from Versioned State](#4-recovering-from-versioned-state)
5. [Breaking a Stuck State Lock](#5-breaking-a-stuck-state-lock)
6. [State Surgery with terraform state Commands](#6-state-surgery-with-terraform-state-commands)
7. [Rebuilding State from Scratch](#7-rebuilding-state-from-scratch)
8. [Preventing State Issues](#8-preventing-state-issues)
9. [Emergency Contacts and Escalation](#9-emergency-contacts-and-escalation)
10. [Post-Incident Checklist](#10-post-incident-checklist)

---

## 1. Overview of State Architecture

### Backend Configuration

All Terraform state is stored in Azure Blob Storage. The backend is bootstrapped by `scripts/bootstrap-state-backend.sh` and lives entirely outside of Terraform management (to avoid the chicken-and-egg problem).

| Component | Value |
|---|---|
| Resource Group | `rg-terraform-state` |
| Storage Account | `stterraform<hash>` (hash derived from subscription ID) |
| Container | `tfstate` |
| Authentication | OIDC (workload identity) |
| Locking mechanism | Azure Blob lease |

### Per-Environment State Files

Each environment has a dedicated, independently-locked state file inside the `tfstate` container:

| Environment | Blob Key |
|---|---|
| dev | `dev.terraform.tfstate` |
| staging | `staging.terraform.tfstate` |
| prod | `prod.terraform.tfstate` |

Isolation means a corruption or lock incident in one environment does not affect the others.

### Safety Features

The following protections are applied to the state backend and are critical to all recovery procedures:

| Feature | Configuration | Purpose |
|---|---|---|
| Blob soft delete | 30-day retention | Recover accidentally deleted state files |
| Blob versioning | Enabled | Restore a previous known-good state version |
| Container soft delete | 30-day retention | Recover accidentally deleted container |
| CanNotDelete lock | Applied to resource group | Prevent accidental destruction of the storage account |
| HTTPS only | Enforced | Prevent plaintext access to state |
| TLS 1.2 minimum | Enforced | Transport security baseline |

### State Locking

Terraform acquires an Azure Blob lease (30-second TTL, auto-renewed) before any write operation. The lock ID is stored inside the `.terraform.lock.hcl` file locally and as metadata on the blob lease. A lock prevents concurrent `plan` or `apply` operations against the same state file.

---

## 2. Common State Issues

### 2.1 State Corruption

**Symptoms:**
- `terraform plan` or `apply` exits with a JSON parse error referencing the state file
- Error message: `Error refreshing state: state snapshot was created by Terraform vX.Y.Z`
- Unexpected resource counts (e.g., 0 resources when many exist)
- State file is present but truncated or malformed

**Likely Causes:**
- A `terraform apply` was interrupted mid-write (process killed, network timeout)
- Manual edits to the state file with incorrect JSON
- Concurrent writes from two processes that both bypassed locking

**Immediate Action:** Do not run `terraform apply`. Proceed to [Section 4](#4-recovering-from-versioned-state) to restore the previous version.

---

### 2.2 Stuck State Lock

**Symptoms:**
- `terraform plan` or `apply` hangs or immediately fails with:
  ```
  Error acquiring the state lock
  Lock Info:
    ID:        <lock-id>
    Path:      tfstate/dev.terraform.tfstate
    Operation: OperationTypeApply
    Who:       runner@ci-host
    Created:   2026-03-03 14:22:00 +0000 UTC
  ```
- The lock was held by a process that died (CI runner crashed, pipeline cancelled, network disruption)

**Do Not:** Force-break a lock while a legitimate `apply` is in progress. Verify the owning process is truly dead before proceeding to [Section 5](#5-breaking-a-stuck-state-lock).

---

### 2.3 State Drift

**Symptoms:**
- `terraform plan` shows a large number of unexpected changes (resources to create or destroy) that do not match recent infrastructure changes
- Resources exist in Azure but Terraform proposes to create them again
- Resources are in the state file but have been manually deleted in Azure

**Likely Causes:**
- Manual changes made in the Azure Portal or via Azure CLI outside of Terraform
- Resources created by another team or automation without being imported into state
- A `terraform apply` completed partially, leaving state and reality out of sync

**Immediate Action:** Review the plan output carefully before applying. Use `terraform refresh` (Terraform 0.15 and earlier) or `terraform apply -refresh-only` (Terraform 1.x) to reconcile state with reality. Proceed to [Section 6](#6-state-surgery-with-terraform-state-commands) for targeted fixes.

---

### 2.4 State File Accidentally Deleted

**Symptoms:**
- `terraform init` or `plan` fails with: `Error: Failed to get existing workspaces: storage: service returned without a response body`
- The blob `dev.terraform.tfstate` no longer appears in the container listing

**Immediate Action:** The blob is protected by soft delete (30-day window). Proceed to [Section 3](#3-recovering-from-soft-deleted-state).

---

### 2.5 Backend Misconfiguration

**Symptoms:**
- `terraform init` fails with authentication errors or resource-not-found for the storage account or container
- Working directory points to the wrong environment's backend

**Check First:**
```bash
# Confirm the active backend configuration
cat environments/<env>/backend.tf

# Confirm you are authenticated correctly
az account show
az account list --output table
```

---

## 3. Recovering from Soft-Deleted State

Use this procedure when a state blob has been deleted and the 30-day soft-delete window has not expired.

### Prerequisites

- Azure CLI installed and authenticated (`az login` or workload identity)
- `Storage Blob Data Contributor` or `Storage Blob Data Owner` role on the storage account
- The CanNotDelete resource lock prevents deletion of the storage account itself, but individual blobs can still be soft-deleted

### Step-by-Step Recovery

**Step 1: Set environment variables.**

```bash
export ENVIRONMENT="dev"   # dev | staging | prod
export RG_NAME="rg-terraform-state"
export SA_NAME="stterraform<hash>"   # replace <hash> with actual value
export CONTAINER_NAME="tfstate"
export BLOB_KEY="${ENVIRONMENT}.terraform.tfstate"
```

**Step 2: Confirm the storage account name.**

```bash
az storage account list \
  --resource-group "$RG_NAME" \
  --query "[].name" \
  --output tsv
```

**Step 3: Retrieve a storage account key for CLI operations.**

```bash
export ACCOUNT_KEY=$(az storage account keys list \
  --account-name "$SA_NAME" \
  --resource-group "$RG_NAME" \
  --query '[0].value' \
  --output tsv)
```

**Step 4: List soft-deleted blobs to confirm the state file is recoverable.**

```bash
az storage blob list \
  --account-name "$SA_NAME" \
  --container-name "$CONTAINER_NAME" \
  --account-key "$ACCOUNT_KEY" \
  --include d \
  --query "[?deleted && name=='${BLOB_KEY}']" \
  --output table
```

Expected output shows the blob with `deleted: true` and a `deletedTime` within the last 30 days. If the blob does not appear, the retention window has expired or the blob was never in this container — escalate to [Section 7](#7-rebuilding-state-from-scratch).

**Step 5: Undelete the blob.**

```bash
az storage blob undelete \
  --account-name "$SA_NAME" \
  --container-name "$CONTAINER_NAME" \
  --name "$BLOB_KEY" \
  --account-key "$ACCOUNT_KEY"
```

**Step 6: Confirm the blob is restored.**

```bash
az storage blob show \
  --account-name "$SA_NAME" \
  --container-name "$CONTAINER_NAME" \
  --name "$BLOB_KEY" \
  --account-key "$ACCOUNT_KEY" \
  --query "{name: name, deleted: deleted, lastModified: properties.lastModified}" \
  --output table
```

The `deleted` field must be `false` (or absent) and `lastModified` should reflect the restoration time.

**Step 7: Validate state by running a plan.**

```bash
cd environments/$ENVIRONMENT
terraform init -reconfigure
terraform plan -out=tfplan.recovery
```

Review the plan carefully. If the plan shows only expected changes (or no changes), the recovery is successful. If the plan shows mass destruction or creation, the undeleted blob may be stale — proceed to [Section 4](#4-recovering-from-versioned-state) to check for a better version.

**Step 8: Clean up the plan file.**

```bash
rm tfplan.recovery
```

---

## 4. Recovering from Versioned State

Use this procedure to restore a prior known-good version of the state file. Versioning creates an immutable history of every write to the blob. This is the primary recovery path for state corruption.

### Prerequisites

- Same role requirements as Section 3
- Blob versioning is enabled (confirmed by `scripts/bootstrap-state-backend.sh`)

### Step-by-Step Recovery

**Step 1: Set environment variables (same as Section 3, Step 1).**

**Step 2: List all available versions of the state blob.**

```bash
az storage blob list \
  --account-name "$SA_NAME" \
  --container-name "$CONTAINER_NAME" \
  --account-key "$ACCOUNT_KEY" \
  --include v \
  --query "[?name=='${BLOB_KEY}'] | sort_by(@, &versionId) | reverse(@)[*].{versionId: versionId, lastModified: properties.lastModified, size: properties.contentLength}" \
  --output table
```

This lists versions in reverse chronological order (newest first). The current live version is the one without a `versionId` in the standard blob listing; all others are historical versions.

**Step 3: Download the target version to inspect it before restoring.**

Replace `<VERSION_ID>` with the `versionId` value from the previous step (e.g., `2026-03-03T13:45:00.1234567Z`).

```bash
az storage blob download \
  --account-name "$SA_NAME" \
  --container-name "$CONTAINER_NAME" \
  --name "$BLOB_KEY" \
  --account-key "$ACCOUNT_KEY" \
  --version-id "<VERSION_ID>" \
  --file "./state-recovery-candidate.json"
```

**Step 4: Inspect the candidate state file.**

```bash
# Confirm it is valid JSON
python3 -m json.tool ./state-recovery-candidate.json > /dev/null && echo "Valid JSON"

# Check Terraform version and resource count
python3 -c "
import json, sys
with open('state-recovery-candidate.json') as f:
    s = json.load(f)
print('Terraform version:', s.get('terraform_version'))
print('Serial:', s.get('serial'))
resources = s.get('resources', [])
print('Resource count:', len(resources))
for r in resources[:10]:
    print(' -', r.get('type'), r.get('name'))
"
```

Confirm the serial number is lower than the corrupted version (a restored version must have a lower serial or it will be rejected). Confirm the resource list looks correct for this environment.

**Step 5: Back up the current (potentially corrupted) state before overwriting.**

```bash
az storage blob download \
  --account-name "$SA_NAME" \
  --container-name "$CONTAINER_NAME" \
  --name "$BLOB_KEY" \
  --account-key "$ACCOUNT_KEY" \
  --file "./state-corrupted-backup-$(date +%Y%m%dT%H%M%S).json"
```

**Step 6: Promote the target version to become the current blob.**

Azure does not have a native "restore version as current" CLI command. The standard approach is to copy the versioned blob over the current blob using a server-side copy.

```bash
# Get the storage account URL
SA_URL="https://${SA_NAME}.blob.core.windows.net"

# Copy the specific version over the current blob
az storage blob copy start \
  --account-name "$SA_NAME" \
  --destination-container "$CONTAINER_NAME" \
  --destination-blob "$BLOB_KEY" \
  --account-key "$ACCOUNT_KEY" \
  --source-uri "${SA_URL}/${CONTAINER_NAME}/${BLOB_KEY}?versionId=<VERSION_ID>"
```

Wait for the copy to complete (it is near-instant for state files):

```bash
az storage blob show \
  --account-name "$SA_NAME" \
  --container-name "$CONTAINER_NAME" \
  --name "$BLOB_KEY" \
  --account-key "$ACCOUNT_KEY" \
  --query "properties.copy.status" \
  --output tsv
```

Status must be `success` before proceeding.

**Step 7: Validate the restored state.**

```bash
cd environments/$ENVIRONMENT
terraform init -reconfigure
terraform plan
```

A clean plan (no unexpected changes) confirms successful recovery. If you see unexpected drift, try an older version or proceed to reconcile with `terraform state` commands in [Section 6](#6-state-surgery-with-terraform-state-commands).

**Step 8: Clean up local files.**

```bash
rm -f ./state-recovery-candidate.json
# Keep the corrupted backup file for post-incident review, then remove it after the incident is closed
```

---

## 5. Breaking a Stuck State Lock

A blob lease lock should be broken only after confirming that the process holding the lock is definitively dead. Breaking an active lock while an `apply` is in progress will corrupt state.

### Confirm the Lock is Orphaned

**Step 1: Identify the lock holder from the Terraform error output.**

The error output includes:
```
Lock Info:
  ID:        <lock-id>
  Who:       runner@ci-agent-07
  Created:   2026-03-03 14:22:00 UTC
  Operation: OperationTypeApply
```

**Step 2: Verify the process is dead.**

- If the lock was held by a CI pipeline, check the pipeline run in your CI system. If the run is cancelled, failed, or timed out, the lock is orphaned.
- If the lock was held by a local developer, contact them directly to confirm the process has exited.
- Check the `Created` time: a lock older than 30 minutes for a typical `apply` is almost certainly orphaned (the Terraform lease auto-renews every 15 seconds; if the process died, the lease expired and Azure reclaimed it automatically after 60 seconds — but Terraform writes a lock metadata blob separately).

**Step 3: Check the current lease state on the blob.**

```bash
export ENVIRONMENT="dev"
export SA_NAME="stterraform<hash>"
export CONTAINER_NAME="tfstate"
export BLOB_KEY="${ENVIRONMENT}.terraform.tfstate"
export ACCOUNT_KEY=$(az storage account keys list \
  --account-name "$SA_NAME" \
  --resource-group "rg-terraform-state" \
  --query '[0].value' \
  --output tsv)

az storage blob show \
  --account-name "$SA_NAME" \
  --container-name "$CONTAINER_NAME" \
  --name "$BLOB_KEY" \
  --account-key "$ACCOUNT_KEY" \
  --query "{leaseState: properties.leaseState, leaseStatus: properties.leaseStatus, leaseDuration: properties.leaseDuration}" \
  --output table
```

If `leaseState` is `leased` and `leaseStatus` is `locked`, the lease is active. If `leaseState` is `expired` or `available`, the Azure-level lease has already released itself, but Terraform's metadata lock file may still exist.

### Breaking the Blob Lease (Azure-Level)

**Step 4: Break the blob lease using Azure CLI.**

```bash
az storage blob lease break \
  --account-name "$SA_NAME" \
  --container-name "$CONTAINER_NAME" \
  --blob-name "$BLOB_KEY" \
  --account-key "$ACCOUNT_KEY"
```

This immediately terminates the blob lease regardless of the original leaseholder. The command returns `0` on success.

**Step 5: Confirm the lease is released.**

```bash
az storage blob show \
  --account-name "$SA_NAME" \
  --container-name "$CONTAINER_NAME" \
  --name "$BLOB_KEY" \
  --account-key "$ACCOUNT_KEY" \
  --query "{leaseState: properties.leaseState, leaseStatus: properties.leaseStatus}" \
  --output table
```

`leaseState` should now be `available` and `leaseStatus` should be `unlocked`.

### Breaking the Terraform Metadata Lock (Terraform-Level)

If Terraform still reports a lock after the blob lease is released, use Terraform's own force-unlock command.

**Step 6: Force-unlock using the lock ID from the error message.**

```bash
cd environments/$ENVIRONMENT
terraform force-unlock <lock-id>
```

Terraform will prompt for confirmation. Type `yes`.

**Step 7: Verify by running a plan.**

```bash
terraform plan
```

If the plan executes without a lock error, the lock is cleared.

---

## 6. State Surgery with terraform state Commands

State surgery involves directly manipulating the state file to reconcile it with reality. These operations must be performed with caution in production. Always back up state before any surgery.

### Before Any Surgery

**Back up the current state:**

```bash
cd environments/$ENVIRONMENT
terraform state pull > ./state-backup-$(date +%Y%m%dT%H%M%S).json
```

Keep this file until the incident is fully closed.

---

### 6.1 Moving a Resource in State (terraform state mv)

Use `terraform state mv` when a resource exists in state under one address and needs to be mapped to a different address (e.g., after a refactor that renamed a resource or moved it into a module).

**Symptom:** `terraform plan` proposes to destroy and recreate a resource that already exists in Azure but whose address changed in the configuration.

```bash
# Syntax
terraform state mv <source-address> <destination-address>

# Example: moving a resource into a module
terraform state mv \
  azurerm_virtual_network.main \
  module.networking.azurerm_virtual_network.main

# Example: renaming a resource
terraform state mv \
  azurerm_resource_group.app \
  azurerm_resource_group.application
```

After the move, run `terraform plan` to confirm the resource shows no changes.

---

### 6.2 Removing a Resource from State (terraform state rm)

Use `terraform state rm` when a resource should be removed from Terraform management without destroying the actual Azure resource (e.g., the resource will be managed by another team or a different Terraform workspace).

**Symptom:** `terraform plan` proposes to destroy a resource that must not be destroyed.

```bash
# Syntax
terraform state rm <resource-address>

# Example: stop managing a specific resource group
terraform state rm azurerm_resource_group.legacy

# Example: stop managing all resources in a module
terraform state rm module.old_networking
```

After removal, the resource will no longer appear in `terraform plan` output. The resource continues to exist in Azure.

**Warning:** Do not use `terraform state rm` to "hide" a resource that Terraform will continue to reference in configuration. This creates drift and will cause errors on the next plan.

---

### 6.3 Importing Existing Resources into State (terraform import)

Use `terraform import` when a resource exists in Azure but is not tracked in state (e.g., it was created manually or by a different pipeline and now needs to be brought under Terraform management).

**Symptom:** `terraform plan` proposes to create a resource that already exists in Azure, or you receive a conflict error during `apply` because the resource already exists.

**Step 1: Add the resource block to your Terraform configuration first.** The import command requires the configuration to already be present.

**Step 2: Find the Azure resource ID.**

```bash
# Example: find a resource group ID
az group show --name "rg-my-app" --query id --output tsv

# Example: find a storage account ID
az storage account show \
  --name "mystorageaccount" \
  --resource-group "rg-my-app" \
  --query id \
  --output tsv
```

**Step 3: Import the resource.**

```bash
# Syntax
terraform import <resource-address> <azure-resource-id>

# Example: import a resource group
terraform import \
  azurerm_resource_group.app \
  /subscriptions/<sub-id>/resourceGroups/rg-my-app

# Example: import a storage account
terraform import \
  azurerm_storage_account.main \
  /subscriptions/<sub-id>/resourceGroups/rg-my-app/providers/Microsoft.Storage/storageAccounts/mystorageaccount
```

**Step 4: Run a plan and reconcile configuration.**

```bash
terraform plan
```

After import, the plan may show configuration differences (e.g., tags or settings that are set in Azure but not yet in the Terraform configuration). Update the configuration to match until the plan shows no changes.

---

### 6.4 Inspecting and Listing State

```bash
# List all resources tracked in state
terraform state list

# Show detailed state for a specific resource
terraform state show azurerm_resource_group.app

# Pull the full raw state JSON (useful for inspection or backup)
terraform state pull | python3 -m json.tool | less
```

---

## 7. Rebuilding State from Scratch

This is the nuclear option. Use it only when:

- The state file is unrecoverable (corruption, no valid versions, outside the soft-delete window)
- Every other recovery option has been exhausted
- You have a complete and accurate inventory of all Azure resources that need to be brought under Terraform management

**Warning:** Rebuilding state in production is a high-risk operation. It requires importing every managed resource one by one. An error during import can cause Terraform to propose destroying real infrastructure on the next `apply`. This procedure requires approval from the on-call engineer and the team lead before execution against staging or production.

### Preparation

**Step 1: Notify all stakeholders.** No `terraform apply` should be run by anyone against this environment during the rebuild.

**Step 2: Export a complete inventory of existing Azure resources in the affected environment.**

```bash
# List all resources in the environment's resource groups
az resource list \
  --resource-group "rg-<environment>-<project>" \
  --output table > ./azure-resource-inventory-$(date +%Y%m%dT%H%M%S).txt
```

Repeat for all resource groups managed by this environment.

**Step 3: Ensure all Terraform configuration files are accurate and match the existing infrastructure.** Do not proceed if the configuration has pending undeployed changes.

### Rebuild Procedure

**Step 4: Remove or archive the corrupted state blob.**

First remove the CanNotDelete lock on the resource group to allow blob-level operations if needed (the lock protects against resource group deletion, not blob modification):

```bash
# The lock is on the resource group, not individual blobs
# Blob delete/overwrite does not require removing the lock
# If you need to delete the container itself, temporarily remove the lock:
# az lock delete --name "terraform-state-lock" --resource-group "$RG_NAME"
# RESTORE THE LOCK IMMEDIATELY AFTER: see Step 10
```

Archive the corrupted blob:

```bash
az storage blob copy start \
  --account-name "$SA_NAME" \
  --destination-container "$CONTAINER_NAME" \
  --destination-blob "${ENVIRONMENT}.terraform.tfstate.corrupted-$(date +%Y%m%dT%H%M%S)" \
  --account-key "$ACCOUNT_KEY" \
  --source-uri "https://${SA_NAME}.blob.core.windows.net/${CONTAINER_NAME}/${BLOB_KEY}"
```

**Step 5: Initialize a fresh state by running `terraform init` and then pushing an empty state.**

```bash
cd environments/$ENVIRONMENT
terraform init -reconfigure

# Verify there is currently no state (or the corrupted state)
terraform state list 2>&1 || true
```

**Step 6: Import resources one by one, starting with dependencies (resource groups first, then dependent resources).**

```bash
# Import resource groups first
terraform import azurerm_resource_group.main \
  /subscriptions/<sub-id>/resourceGroups/rg-<env>-<project>

# Then import resources in dependency order
# Virtual networks before subnets, key vaults before secrets, etc.
terraform import azurerm_virtual_network.main \
  /subscriptions/<sub-id>/resourceGroups/rg-<env>-<project>/providers/Microsoft.Network/virtualNetworks/<vnet-name>

# ... continue for all resources
```

After each import batch, run:

```bash
terraform plan
```

and verify the plan shows only remaining-to-import resources as new, and no unexpected destroys.

**Step 7: After all resources are imported, run a full plan and verify zero changes.**

```bash
terraform plan -detailed-exitcode
```

Exit code `0` = no changes. Exit code `2` = changes pending. Exit code `1` = error.

A clean zero-change plan confirms the rebuilt state fully matches the running infrastructure.

**Step 8: Back up the rebuilt state immediately.**

```bash
terraform state pull > ./state-rebuilt-$(date +%Y%m%dT%H%M%S).json
```

Store this file in a secure location outside the repository.

**Step 9: Document every resource that was imported and any configuration changes required.**

**Step 10: Verify the CanNotDelete lock is still in place on the resource group.**

```bash
az lock list \
  --resource-group "rg-terraform-state" \
  --query "[?name=='terraform-state-lock']" \
  --output table
```

If the lock is missing (e.g., it was removed during Step 4), restore it immediately:

```bash
az lock create \
  --name "terraform-state-lock" \
  --resource-group "rg-terraform-state" \
  --lock-type CanNotDelete \
  --notes "Protects Terraform state backend from accidental deletion"
```

---

## 8. Preventing State Issues

### 8.1 Never Run terraform apply Locally Against Shared Environments

All applies to `staging` and `prod` must go through CI/CD. Local applies bypass audit logging, can race with CI pipelines, and are more likely to be interrupted. The `dev` environment allows local applies for debugging only.

### 8.2 Always Plan Before Applying

```bash
terraform plan -out=tfplan
terraform apply tfplan
```

Using a saved plan file ensures that the apply executes exactly what was reviewed. An unsaved `terraform apply` re-runs planning and can pick up configuration changes that happened between review and apply.

### 8.3 Protect State Files with Access Control

The storage account uses OIDC (workload identity) for authentication. Do not generate long-lived storage account keys for automation. Rotate any existing keys immediately if they are leaked.

```bash
# Rotate a storage account key (invalidates the old key immediately)
az storage account keys renew \
  --account-name "$SA_NAME" \
  --resource-group "rg-terraform-state" \
  --key primary
```

### 8.4 Enforce Locking — Never Use -lock=false

Do not pass `-lock=false` to any Terraform command. This flag disables the blob lease mechanism and allows concurrent writes that will corrupt state. If you encounter a lock, investigate and break it using the procedure in [Section 5](#5-breaking-a-stuck-state-lock) rather than bypassing it.

### 8.5 Tag All Terraform-Managed Resources Consistently

Consistent tagging makes it possible to inventory Azure resources and cross-reference them with state during recovery. Enforce a `managed_by = terraform` tag on all resources via an Azure Policy or a Terraform `default_tags` provider block.

### 8.6 Back Up State Before Major Operations

Before any large refactor, module restructure, or version upgrade:

```bash
cd environments/$ENVIRONMENT
terraform state pull > ./state-backup-before-<operation>-$(date +%Y%m%dT%H%M%S).json
```

Store this backup outside the working directory (e.g., a secure storage location or a private artifact store).

### 8.7 Monitor State Lock Duration

Set up an Azure Monitor alert on blob lease activity for the `tfstate` container. A lease held for more than 15 minutes is abnormal and warrants investigation.

### 8.8 Use Separate Service Principals per Environment

The OIDC workload identity configuration should use a different service principal (or managed identity) per environment. This ensures that a compromised dev credential cannot access prod state.

### 8.9 Do Not Edit State Files Manually

State files are JSON but they contain computed checksums and serial numbers. Manual edits almost always produce invalid state. Use `terraform state mv`, `terraform state rm`, and `terraform import` for all state modifications.

### 8.10 Validate Configuration Before Applying

```bash
terraform validate
terraform fmt -check
```

Run these checks in CI on every pull request to catch configuration errors before they reach apply.

---

## 9. Emergency Contacts and Escalation

### Escalation Tiers

| Tier | When to Escalate | Contact |
|---|---|---|
| Tier 1 | State lock stuck, soft-delete recovery, minor drift | On-call Platform Engineer |
| Tier 2 | State corruption, version rollback, state surgery | Platform Engineering Team Lead |
| Tier 3 | State rebuild from scratch, production data loss risk | Platform Engineering Lead + Engineering Manager |

### Escalation Guidelines

- **Production state incidents are Tier 2 by default.** Do not attempt solo production state surgery without notifying the team lead.
- **Declare an incident** in your incident management system before beginning any Tier 2 or Tier 3 procedure. This creates an audit trail and ensures the right people are notified.
- **Do not rush.** Most state recovery procedures are reversible (soft delete, versioning). Taking an extra 10 minutes to understand the situation prevents hours of additional recovery work.
- **Communicate status** in the incident channel at least every 15 minutes during active recovery.

### Useful Reference Links

- [Azure Blob Soft Delete Documentation](https://learn.microsoft.com/en-us/azure/storage/blobs/soft-delete-blob-overview)
- [Azure Blob Versioning Documentation](https://learn.microsoft.com/en-us/azure/storage/blobs/versioning-overview)
- [Terraform AzureRM Backend Documentation](https://developer.hashicorp.com/terraform/language/backend/azurerm)
- [Terraform State Command Reference](https://developer.hashicorp.com/terraform/cli/commands/state)
- [Terraform force-unlock Command](https://developer.hashicorp.com/terraform/cli/commands/force-unlock)

---

## 10. Post-Incident Checklist

Complete this checklist after every state recovery incident before declaring the incident resolved.

### Immediate Verification

- [ ] `terraform plan` runs cleanly with zero unexpected changes against the affected environment
- [ ] `terraform state list` returns the expected resource count
- [ ] No blob lease is currently held on the recovered state file
- [ ] The CanNotDelete resource lock is confirmed present on `rg-terraform-state`
- [ ] Blob versioning and soft delete are still enabled on the storage account

### Cleanup

- [ ] All local state backup files have been reviewed and either archived securely or deleted
- [ ] Any temporary storage account keys that were generated for recovery have been rotated
- [ ] The `state-recovery-candidate.json` and other temporary files are removed from working directories
- [ ] If the resource lock was temporarily removed during recovery, it has been restored

### Documentation

- [ ] The incident has been logged with: timeline, root cause, environments affected, recovery steps taken, and duration
- [ ] Any configuration or process changes made during recovery are reflected in the codebase and committed
- [ ] If state surgery was performed, a comment or commit message documents what was moved, removed, or imported and why

### Process Improvement

- [ ] Root cause identified: what allowed the state issue to occur?
- [ ] Action items created to prevent recurrence (e.g., CI guard, access control change, alerting)
- [ ] This runbook reviewed: are any steps inaccurate or missing based on the actual incident experience? If so, update this document.
- [ ] Lessons learned shared with the broader team in a blameless post-mortem

---

*This runbook is a living document. If you follow a procedure and find that a step is incorrect, ambiguous, or missing, update this file as part of the incident post-mortem. The goal is that the next on-call engineer who opens this document can resolve a state incident without additional guidance.*
