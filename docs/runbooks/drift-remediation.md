# Runbook: Infrastructure Drift Detection and Remediation

**Version:** 1.0
**Last Updated:** 2026-03-03
**Owner:** Platform Team
**Scope:** All environments (dev, staging, prod)

---

## Table of Contents

1. [What Is Infrastructure Drift and Why It Matters](#1-what-is-infrastructure-drift-and-why-it-matters)
2. [How Drift Detection Works in This Project](#2-how-drift-detection-works-in-this-project)
3. [Reading Drift Detection Reports](#3-reading-drift-detection-reports)
4. [Drift Classification](#4-drift-classification)
5. [Remediation Strategies by Category](#5-remediation-strategies-by-category)
6. [Applying Fixes Through the CI/CD Pipeline](#6-applying-fixes-through-the-cicd-pipeline)
7. [When to Accept Drift](#7-when-to-accept-drift)
8. [Importing Manually-Created Resources](#8-importing-manually-created-resources)
9. [Preventing Drift](#9-preventing-drift)
10. [Metrics and SLOs for Drift Management](#10-metrics-and-slos-for-drift-management)

---

## 1. What Is Infrastructure Drift and Why It Matters

Infrastructure drift is the condition where the actual state of deployed cloud resources diverges from the desired state declared in Terraform configuration. In Azure, drift accumulates when resources are modified directly through the Azure Portal, Azure CLI, ARM templates run outside Terraform, automated platform operations (e.g. Azure auto-scaling, Azure Policy remediation tasks), or emergency manual changes made during incidents.

### Why Drift Is Dangerous

**Reproducibility breaks.** If a resource was manually reconfigured, destroying and redeploying the environment will not reproduce the current working state. This makes disaster recovery and blue/green deployments unreliable.

**Security posture degrades silently.** A firewall rule added manually to allow emergency access, a RBAC assignment granted ad hoc, or a storage account made publicly accessible for debugging are all examples of drift that represent active security risk with no automated audit trail.

**Cost control fails.** SKU upgrades, additional replicas, or premium features enabled manually inflate costs without corresponding Terraform records or change reviews.

**Audit and compliance gaps open.** Regulated workloads (PCI, SOC 2, ISO 27001) require that infrastructure state matches reviewed and approved configuration. Out-of-band changes are a compliance finding.

**Cascading plan failures.** When Terraform detects drift on a dependency resource, it may plan destructive changes on downstream resources that depend on that attribute. A drifted VNet address space, for example, can cause Terraform to want to recreate subnets and everything attached to them.

The goal of this project's drift detection system is to surface these conditions daily, before they compound into large, risky remediation events.

---

## 2. How Drift Detection Works in This Project

### Scheduled Pipeline

The primary drift detection mechanism is the Azure DevOps pipeline defined at `pipelines/drift-check.yml`. It runs on a daily schedule at **06:00 UTC** against the `main` branch, with `always: true` ensuring it runs even when there are no code changes. All three environments run in parallel with no stage dependencies between them.

```
06:00 UTC daily
       |
       +-- DevDriftCheck    (environments/dev,     azure-dev service connection)
       +-- StagingDriftCheck (environments/staging, azure-staging service connection)
       +-- ProdDriftCheck   (environments/prod,    azure-prod service connection)
```

Each stage uses the shared template `pipelines/templates/drift-detection.yml`, which:

1. Authenticates to Azure using Workload Identity Federation (OIDC) via the `AzureCLI@2` task — no long-lived secrets.
2. Runs `terraform init -input=false` to ensure the backend and providers are current.
3. Runs `terraform plan -detailed-exitcode -var-file=terraform.tfvars -input=false -out=drift.tfplan`.
4. Interprets the exit code (see below).
5. If drift is detected, runs `terraform show drift.tfplan -no-color` to emit the full plan diff into the pipeline log.
6. Sets the pipeline output variable `driftDetected` to `true` or `false`.

### Exit Code Semantics

`terraform plan -detailed-exitcode` uses a three-value exit code contract:

| Exit Code | Meaning |
|-----------|---------|
| `0` | Success, no changes — infrastructure matches configuration exactly |
| `1` | Error — plan failed; investigate pipeline logs for provider errors, auth failures, or state backend issues |
| `2` | Success, changes present — drift detected; the plan output describes what changed |

The template uses `set +e` / `set -e` around the plan command to capture exit code 2 without failing the pipeline step, and then branches on the value.

### Manual Drift Check

To run drift detection locally or on demand:

```bash
# Check a single environment
make drift ENV=dev
make drift ENV=staging
make drift ENV=prod

# The make target exits with code 2 if drift is found, 0 if clean, non-zero on error
```

The `drift` Makefile target runs `terraform plan -detailed-exitcode -var-file=<env>.tfvars` from `environments/<env>/`. It prints color-coded output: green for no drift, yellow for drift detected, red for errors.

### Authentication

The pipeline authenticates using Workload Identity Federation with service connections named `azure-dev`, `azure-staging`, and `azure-prod`. The OIDC tokens are passed as environment variables:

```
ARM_USE_OIDC=true
ARM_CLIENT_ID=$servicePrincipalId
ARM_TENANT_ID=$tenantId
```

No subscription ID or client secret is set in the template; these must be configured in the service connection and backend configuration for each environment.

---

## 3. Reading Drift Detection Reports

When the pipeline detects drift (exit code 2), it calls `terraform show drift.tfplan -no-color` and emits the full plan to the pipeline log. The output uses standard Terraform plan notation.

### Locating the Report

In Azure DevOps:

1. Navigate to **Pipelines > Drift Detection**.
2. Open the most recent run.
3. Select the stage for the environment you are investigating (e.g. `Prod Drift Check`).
4. Open the `Detect Drift - Prod` job.
5. Expand the `Terraform Plan - Drift Detection (prod)` step.
6. Look for the `##[warning]Drift detected` line, followed by the `##[section]Drift details:` block containing the full plan.

### Plan Output Structure

A typical drift plan output looks like this:

```
Terraform will perform the following actions:

  # azurerm_storage_account.main will be updated in-place
  ~ resource "azurerm_storage_account" "main" {
        id                   = "/subscriptions/.../storageAccounts/platformdevsa"
      ~ min_tls_version      = "TLS1_2" -> "TLS1_0"
      ~ allow_blob_public_access = false -> true
        # (18 unchanged attributes hidden)
    }

  # azurerm_network_security_group.app will be updated in-place
  ~ resource "azurerm_network_security_group" "app" {
      ~ security_rule {
          + name             = "AllowRDP_Emergency"
          + priority         = 100
          + direction        = "Inbound"
          + access           = "Allow"
          + protocol         = "Tcp"
          + destination_port_range = "3389"
            # ...
        }
    }

Plan: 0 to add, 2 to change, 0 to destroy.
```

### Reading the Symbols

| Symbol | Meaning |
|--------|---------|
| `~` | Resource or attribute will be updated in-place |
| `+` | Resource or attribute will be added |
| `-` | Resource or attribute will be removed |
| `-/+` | Resource will be destroyed and recreated |
| `->` | Current value (left) will change to desired value (right) |
| `(known after apply)` | Value is computed and not yet known |
| `# (N unchanged attributes hidden)` | These attributes match; suppressed for brevity |

### Summary Line

Always check the summary line at the bottom of the plan:

```
Plan: X to add, Y to change, Z to destroy.
```

- Any `destroy` count in prod requires immediate escalation and review before remediation.
- A high `change` count on a single resource often indicates tag or metadata drift rather than structural changes — read the full resource block.

---

## 4. Drift Classification

Not all drift carries equal risk. Before taking action, classify the drift to determine urgency and the appropriate remediation path.

### Category A: Cosmetic Drift

**Definition:** Changes that do not affect functionality, security, access control, or cost. These are typically tag mismatches, description field changes, or display-name variations.

**Examples:**
- A tag value was updated manually (e.g. `owner = "alice"` changed to `owner = "alice.smith@company.com"`)
- A resource group description was changed
- Azure automatically populated a field that Terraform does not manage (e.g. `last_modified_at`)

**Risk:** Low. No immediate operational, security, or cost impact.

**SLO:** Resolve within 5 business days.

**Action:** Apply `terraform apply` via the standard pipeline to restore declared state, or use `lifecycle { ignore_changes }` if the field is managed by an external process (see Section 7).

---

### Category B: Functional Drift

**Definition:** Changes that alter the behavior, configuration, capacity, or connectivity of infrastructure without introducing a direct security vulnerability.

**Examples:**
- A VM SKU was scaled up manually during a load event
- A storage account replication type changed from `LRS` to `GRS`
- A Key Vault soft-delete retention period was modified
- A subnet address prefix was extended
- A diagnostic settings category was removed

**Risk:** Medium. May cause cost overruns, inconsistency between environments, or unexpected behavior when Terraform reconciles.

**SLO:** Resolve within 2 business days for non-prod, 1 business day for prod.

**Action:** Determine whether the change should be made permanent (update Terraform config and apply) or reverted (apply without config change). See Section 5.

---

### Category C: Security Drift

**Definition:** Changes that weaken access controls, expose data, open network paths, or grant elevated permissions.

**Examples:**
- A storage account's `allow_blob_public_access` changed to `true`
- An NSG rule was added that opens an inbound port (especially 22, 3389, 1433, 5432)
- A Key Vault firewall was disabled or a permitted network was added
- A `min_tls_version` was downgraded
- A RBAC assignment was added at subscription scope
- A private endpoint was removed, exposing a service to the public internet
- Diagnostic logging was disabled on a security-critical resource

**Risk:** High. Must be treated as a potential active security incident until proven otherwise.

**SLO:** Acknowledge within 1 hour. Remediate within 4 hours for prod, 8 hours for non-prod.

**Action:** Immediately assess whether the change was malicious or accidental. Escalate to the security team. Revert via Terraform apply as soon as possible. Review Azure Activity Log for the identity that made the change.

---

### Classification Decision Tree

```
Drift detected
      |
      v
Does the change affect network access, IAM, encryption,
TLS settings, public access, or audit logging?
      |
     YES --> Category C: Security Drift (escalate immediately)
      |
      NO
      |
      v
Does the change affect SKU, capacity, replication,
connectivity, or runtime behavior?
      |
     YES --> Category B: Functional Drift
      |
      NO
      |
      v
Tags, descriptions, metadata only?
      |
     YES --> Category A: Cosmetic Drift
```

---

## 5. Remediation Strategies by Category

### Category A: Cosmetic Drift

**Option 1 — Revert to declared state (recommended)**

No configuration change is needed. Simply run the standard apply pipeline for the environment. Terraform will rewrite the tags or metadata back to the declared values.

```bash
# Verify the plan only touches cosmetic fields
make drift ENV=dev

# Proceed through the normal pipeline (see Section 6)
```

**Option 2 — Accept the drift with `ignore_changes`**

If the field is legitimately managed outside Terraform (e.g. an external CMDB system writes tags), add a lifecycle block to suppress future drift noise:

```hcl
resource "azurerm_resource_group" "main" {
  # ...
  lifecycle {
    ignore_changes = [tags["last_synced_by_cmdb"]]
  }
}
```

Commit the change, open a PR, and apply through the pipeline.

---

### Category B: Functional Drift

**Decision: revert or reconcile?**

Before acting, determine intent:

- Was the change made as a permanent operational decision (e.g. a capacity upgrade that should become the new baseline)?
- Or was it a temporary workaround that should be undone?

**Path 1 — Revert: restore declared state**

The manual change is not sanctioned. Apply the existing Terraform configuration to restore the resource to its declared state.

```bash
# Confirm the plan only reverts the drifted resource
make drift ENV=staging

# Apply via pipeline (see Section 6)
```

**Path 2 — Reconcile: update Terraform to match reality**

The manual change was a deliberate, permanent improvement. Update the Terraform configuration to declare the new desired state, then apply.

```bash
# 1. Update the relevant .tf file or .tfvars
#    Example: change VM SKU
#    In environments/prod/prod.tfvars:
#      vm_sku = "Standard_D4s_v3"   # was Standard_D2s_v3

# 2. Verify the plan shows no changes (drift is now codified)
make drift ENV=prod

# 3. Open PR, get approval, merge, pipeline applies
```

**Handling destructive reconciliation**

If the drift plan shows a `-/+` (destroy and recreate) action, do not apply blindly. Destructive operations on stateful resources (databases, storage accounts, Key Vaults) require a maintenance window, data backup verification, and explicit approval.

Check whether `prevent_destroy = true` is set in the lifecycle block of high-value resources. If not, add it as a safeguard before proceeding.

---

### Category C: Security Drift

**Immediate containment first, then remediation.**

Step 1 — Assess blast radius. Check the Azure Activity Log to identify who made the change and when:

```bash
az monitor activity-log list \
  --resource-group <rg-name> \
  --start-time $(date -u -d '48 hours ago' +%Y-%m-%dT%H:%M:%SZ) \
  --query "[?operationName.value != 'Microsoft.Resources/deployments/write'].{time:eventTimestamp, caller:caller, op:operationName.value, status:status.value}" \
  --output table
```

Step 2 — Determine if the change was authorized. Contact the identity shown in the Activity Log. If the change cannot be attributed to a known, approved action, treat it as a security incident and engage the security team immediately.

Step 3 — Revert immediately. Do not wait for the scheduled pipeline. Trigger a manual apply:

```bash
# From a local workstation with appropriate credentials:
cd environments/prod
terraform init -input=false
terraform plan -detailed-exitcode -var-file=prod.tfvars -out=remediation.tfplan

# Review the plan carefully — confirm it only reverts the security change
terraform show remediation.tfplan

# Apply
terraform apply remediation.tfplan
```

Step 4 — Verify remediation. Re-run drift detection to confirm zero drift:

```bash
make drift ENV=prod
# Expected: "==> No drift"
```

Step 5 — Post-incident. File a post-mortem. Add an Azure Policy assignment or RBAC restriction to prevent the same change class from happening again (see Section 9).

---

## 6. Applying Fixes Through the CI/CD Pipeline

All remediation that involves changing infrastructure state — whether reverting drift or codifying a manual change — must go through the standard CI/CD pipeline. Direct `terraform apply` from a local workstation is reserved for emergency security remediation only, and must be followed up with a pipeline-driven verification run.

### Standard Remediation Flow

```
1. Identify drift (scheduled pipeline or make drift)
       |
       v
2. Classify drift (Section 4)
       |
       v
3. Determine action (revert or reconcile)
       |
       v
4. If reconciling: update .tf / .tfvars files
   If reverting:   no config changes needed
       |
       v
5. Open pull request on a feature branch
       |
       v
6. CI pipeline runs on PR:
   - terraform fmt
   - terraform validate
   - tflint
   - terraform test
       |
       v
7. PR review and approval
       |
       v
8. Merge to main
       |
       v
9. CD pipeline applies to target environment
       |
       v
10. Next scheduled drift check confirms zero drift
```

### Triggering a Manual Pipeline Run

When you need to apply a fix immediately without waiting for the next scheduled run:

1. In Azure DevOps, navigate to **Pipelines > Drift Detection**.
2. Click **Run pipeline**.
3. Select the `main` branch.
4. Click **Run**.

Alternatively, for the full CD pipeline (which actually applies changes), navigate to the environment-specific CD pipeline and trigger a run after merging your fix to `main`.

### Environment Promotion Order

Always apply remediation in environment order to validate before promoting:

```
dev  -->  staging  -->  prod
```

Do not apply directly to prod if the same change can be tested in dev or staging first. The exception is a security revert in prod that must happen immediately — apply to prod first, then reconcile lower environments.

### Verifying the Fix

After the pipeline completes, confirm drift is resolved:

```bash
make drift ENV=dev    # Exit 0 = clean
make drift ENV=staging
make drift ENV=prod
```

The next scheduled 06:00 UTC run will also confirm zero drift. If the pipeline run shows drift immediately after remediation, investigate whether a competing process is re-introducing the change.

---

## 7. When to Accept Drift

Some drift is legitimate and should not be reverted. Accepting drift means codifying a `lifecycle { ignore_changes }` block in Terraform so the field is no longer tracked, or updating the Terraform declaration to match reality.

### Legitimate Scenarios for Accepting Drift

**Platform-managed fields.** Azure silently populates or modifies certain attributes that Terraform tracks but that are not meaningfully controllable. Examples include:

- `identity.principal_id` on managed identity resources
- `etag` fields on various resources
- Auto-generated `default_action` values on new resource types

Use `ignore_changes` for these fields.

**Externally-managed tags.** If your organization uses a CMDB, cost allocation tool, or governance system that writes tags to resources directly, those tag keys will drift every time the external system runs. Rather than fighting this, use `ignore_changes` for the specific tag keys managed externally:

```hcl
lifecycle {
  ignore_changes = [
    tags["CostCenter"],
    tags["BusinessUnit"],
  ]
}
```

**Auto-scaling adjustments.** If a resource's capacity (instance count, SKU tier) is managed by Azure Autoscale, the live value will diverge from the Terraform-declared baseline. Configure `ignore_changes` on the relevant capacity attribute and manage scaling policy via Terraform instead of the instance count directly.

**Emergency break-glass changes.** If a change was made during a production incident under a documented break-glass procedure, it may be intentional and have already received post-hoc approval. In this case, reconcile Terraform to match rather than revert.

### Process for Accepting Drift

1. Document the decision in a comment in the relevant `.tf` file explaining why the field is ignored.
2. Add the `ignore_changes` lifecycle block.
3. Open a PR with the change, referencing the incident ticket or change request.
4. After merge, verify `make drift ENV=<env>` returns exit code 0.

### What You Must Not Accept

- Security-relevant attribute drift (TLS versions, public access flags, firewall rules, RBAC assignments).
- Changes that affect data durability (replication type, backup retention, soft-delete settings).
- Changes that affect resource identity or naming (these often cannot be accepted without destroying and recreating resources anyway).

---

## 8. Importing Manually-Created Resources

When a resource was created outside Terraform and needs to be brought under management, use `terraform import`. This project provides `scripts/import-helper.sh` to streamline the process with before/after plan comparison.

### Finding the Resource ID

Before importing, retrieve the Azure resource ID:

```bash
# Resource group
az group show --name <rg-name> --query id -o tsv

# Storage account
az storage account show --name <sa-name> --resource-group <rg-name> --query id -o tsv

# Key Vault
az keyvault show --name <kv-name> --resource-group <rg-name> --query id -o tsv

# Virtual network
az network vnet show --name <vnet-name> --resource-group <rg-name> --query id -o tsv

# Generic: list all resources in a resource group
az resource list --resource-group <rg-name> --query "[].{name:name, id:id, type:type}" -o table
```

### Writing the Terraform Configuration First

Before importing, write the Terraform resource block that will manage the resource. It does not need to be exact — import will bring the state in, and the subsequent plan will show what attributes need adjustment.

```hcl
# Example: manually created storage account
resource "azurerm_storage_account" "imported_sa" {
  name                = "platformprodimportedsa"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  account_tier        = "Standard"
  account_replication_type = "LRS"

  tags = local.common_tags
}
```

### Using the Import Helper Script

```bash
cd environments/dev   # or staging, prod

# Syntax: ./scripts/import-helper.sh <terraform_resource_address> <azure_resource_id>
../../scripts/import-helper.sh \
  azurerm_storage_account.imported_sa \
  /subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/platform-dev-rg/providers/Microsoft.Storage/storageAccounts/platformprodimportedsa
```

The script:
1. Captures a pre-import plan for comparison.
2. Runs `terraform import` to add the resource to state.
3. Runs a post-import plan to show remaining configuration drift.
4. Diffs the two plans to highlight what changed.

### Reconciling After Import

After import, the post-import plan will typically show attribute differences between your Terraform declaration and the actual resource configuration. Work through each difference:

- **If Terraform's value is correct:** leave it — `terraform apply` will reconcile the resource.
- **If the live value is correct and intentional:** update your `.tf` declaration to match, or use `ignore_changes`.
- **If the attribute causes a destroy/recreate:** evaluate carefully; you may need to retain `ignore_changes` for that attribute until a maintenance window allows safe recreation.

Run `make drift ENV=<env>` after completing reconciliation. The goal is exit code 0 — no planned changes.

### Native Terraform Import Block (Terraform 1.5+)

For resources with complex IDs or when scripting bulk imports, use the native `import` block instead:

```hcl
# In a temporary imports.tf file (remove after applying)
import {
  to = azurerm_storage_account.imported_sa
  id = "/subscriptions/.../storageAccounts/platformprodimportedsa"
}
```

```bash
terraform plan -generate-config-out=generated.tf   # auto-generates resource config
terraform apply
```

Remove the `import` block and `generated.tf` after the import is complete and the configuration has been cleaned up and committed.

---

## 9. Preventing Drift

Detection and remediation are reactive. The strongest controls are those that prevent unauthorized changes from reaching production in the first place.

### Azure RBAC Restrictions

Apply least-privilege RBAC to limit who can modify infrastructure resources directly.

**Production principle:** No human should hold `Contributor` or `Owner` at the subscription or resource group level in production. Use time-bound Privileged Identity Management (PIM) role activations for emergency access, and require justification and approval.

**Service principal scope:** The Terraform service principals (`azure-dev`, `azure-staging`, `azure-prod`) should hold `Contributor` only on the specific resource groups they manage, not at subscription scope.

**Recommended production RBAC posture:**

| Role | Scope | Assignment |
|------|-------|------------|
| `Reader` | Subscription | All platform engineers |
| `Contributor` | Specific resource groups | Terraform SP only (via pipeline) |
| `Owner` | Subscription | Break-glass account (PIM, time-bound) |
| `User Access Administrator` | Subscription | Identity team SP only |

```hcl
# Enforce via Terraform — do not assign RBAC manually
resource "azurerm_role_assignment" "terraform_sp_contributor" {
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Contributor"
  principal_id         = var.terraform_sp_object_id
}
```

### Azure Policy

Azure Policy provides a declarative, platform-enforced layer of governance that operates independently of Terraform. Policies can `Audit` (report violations), `Deny` (block the operation), or `Modify` (auto-remediate by adding/changing attributes).

**High-value policies for drift prevention:**

| Policy | Effect | Purpose |
|--------|--------|---------|
| Require a tag on resource groups | `Deny` | Enforce `managed_by=terraform` tag presence |
| Allowed locations | `Deny` | Restrict resource creation to approved Azure regions |
| Allowed resource types | `Audit` | Alert on resource types not in the approved list |
| Storage accounts should use customer-managed keys | `Audit` | Detect encryption drift |
| Secure transfer to storage accounts | `Deny` | Block disabling HTTPS requirement |
| Minimum TLS version for storage | `Deny` | Block TLS 1.0/1.1 on storage accounts |
| Network access to storage accounts | `Audit` | Alert when public access is enabled |
| Key Vault should have firewall enabled | `Deny` | Block disabling Key Vault network restrictions |
| Azure Defender for ... | `AuditIfNotExists` | Alert when security plans are removed |

Policy assignments are managed in `policies/assignments/`. Add new assignments there rather than through the Portal to maintain state.

**Deny policy example — block public blob access:**

```hcl
resource "azurerm_policy_assignment" "no_public_blob" {
  name                 = "deny-public-blob-access"
  scope                = data.azurerm_subscription.current.id
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/..."
  display_name         = "Deny public blob access on storage accounts"
  enforce              = true  # set to false for Audit mode
}
```

### Resource Locks

For critical resources that should never be deleted or modified outside Terraform, apply Azure resource locks:

```hcl
resource "azurerm_management_lock" "state_storage_lock" {
  name       = "terraform-state-lock"
  scope      = azurerm_storage_account.tfstate.id
  lock_level = "CanNotDelete"
  notes      = "Terraform state backend. Do not delete."
}
```

Use `CanNotDelete` for most resources. Use `ReadOnly` only on truly immutable resources, as it blocks all writes including Terraform's own plan operations.

### Drift-Aware Deployment Gates

Consider adding a deployment gate to the CD pipeline that fails the deployment if drift is detected before apply. This ensures that unexpected out-of-band changes are surfaced before Terraform's apply potentially overwrites them silently:

```yaml
# In environment-cd.yml, before the apply step:
- template: templates/drift-detection.yml
  parameters:
    workingDirectory: '$(System.DefaultWorkingDirectory)/environments/$(environment)'
    varFile: 'terraform.tfvars'
    serviceConnection: 'azure-$(environment)'
    environment: '$(environment)'

- script: |
    if [ "$(driftCheck.driftDetected)" = "true" ]; then
      echo "##[error]Pre-apply drift detected. Investigate before applying."
      exit 1
    fi
  displayName: 'Gate: Fail if pre-apply drift present'
```

### Monitoring and Alerting

Configure Azure Monitor alerts on the Activity Log to fire when high-risk operations are performed on production resources:

- Any write to `Microsoft.Network/networkSecurityGroups`
- Any write to `Microsoft.Storage/storageAccounts` setting `allowBlobPublicAccess=true`
- Any `Microsoft.Authorization/roleAssignments/write` at subscription scope
- Any `Microsoft.KeyVault/vaults/write` modifying network rules

These alerts provide real-time notification of drift-causing events, allowing faster response than waiting for the 06:00 UTC scheduled detection.

---

## 10. Metrics and SLOs for Drift Management

### Key Metrics

Track the following metrics on a per-environment basis. Publish them to a shared dashboard visible to the platform team.

**Drift Frequency**
- Definition: Number of scheduled pipeline runs per week that return exit code 2 (drift detected).
- How to track: Query Azure DevOps pipeline run results for the `Drift Detection` pipeline. Count runs where the `driftDetected` output variable is `true`.
- Target: See SLOs below.

**Drift Age**
- Definition: Time elapsed between drift being first detected (first pipeline run showing drift) and being fully remediated (first subsequent run showing zero drift for that environment).
- How to track: Record detection timestamp from pipeline logs; record remediation timestamp from the first clean run.
- Target: See SLOs below.

**Drift Recurrence Rate**
- Definition: Percentage of remediated drift events where the same resource drifts again within 30 days.
- How to track: Tag drift incidents with the affected resource address; compare across time windows.
- Target: < 10%. High recurrence indicates a systemic process gap, not just a one-time mistake.

**Resources Under Management**
- Definition: Percentage of production Azure resources tracked in Terraform state vs. total resources in the subscription.
- How to track: `az resource list --subscription <id> --query "length([])"` vs. Terraform state resource count.
- Target: > 95% for production subscriptions.

**Mean Time to Detect (MTTD)**
- Definition: Average time between when a drift-causing change occurs in Azure and when the drift pipeline first reports it.
- How to track: Compare Activity Log event timestamp to pipeline run timestamp.
- Upper bound: 24 hours (one full detection cycle at 06:00 UTC). Reduce by running more frequent scheduled checks if MTTD SLO is missed.

**Mean Time to Remediate (MTTR)**
- Definition: Average time from drift detection to confirmed zero-drift state for that environment.
- How to track: Pipeline run timestamps.

---

### Service Level Objectives

| Category | MTTD | Acknowledge | Remediate (Non-Prod) | Remediate (Prod) |
|----------|------|-------------|----------------------|------------------|
| A — Cosmetic | 24 hours | Next business day | 5 business days | 5 business days |
| B — Functional | 24 hours | Same business day | 2 business days | 1 business day |
| C — Security | 24 hours | 1 hour | 8 hours | 4 hours |

**SLO Breach Escalation:**

- Category A breach: Team lead notified; logged in backlog.
- Category B breach: Engineering manager notified; P2 incident opened.
- Category C breach: On-call paged immediately; P1 incident opened; security team engaged.

---

### Reporting

Produce a weekly drift summary at the start of each week covering the prior 7 days. Include:

1. Number of detection runs per environment (target: 7 per environment per week).
2. Number of drift events detected per environment.
3. Classification breakdown (A/B/C) for each drift event.
4. Remediation status for each open drift event (open, in-progress, resolved, accepted).
5. SLO compliance rate for resolved events.
6. Any new `ignore_changes` additions or resource imports completed.
7. Azure Policy or RBAC changes made to prevent recurrence.

Share the summary in the platform team channel and link the Azure DevOps pipeline dashboard.

---

## Appendix: Quick Reference

### Exit Code Summary

| `make drift` Exit Code | Meaning | Action |
|------------------------|---------|--------|
| `0` | No drift | None required |
| `2` | Drift detected | Classify and remediate |
| Any other | Error | Investigate pipeline logs; check auth and state backend |

### Common Terraform Commands for Drift Remediation

```bash
# Check drift for an environment
make drift ENV=<dev|staging|prod>

# Run plan with detailed output saved to file
cd environments/<env>
terraform plan -detailed-exitcode -var-file=<env>.tfvars -out=remediation.tfplan

# Inspect the saved plan before applying
terraform show remediation.tfplan

# Apply only the saved plan (no interactive prompt)
terraform apply remediation.tfplan

# Import a manually-created resource
../../scripts/import-helper.sh <resource_address> <azure_resource_id>

# Show current state for a specific resource
terraform state show <resource_address>

# List all resources in state
terraform state list

# Remove a resource from state without destroying it (use with extreme caution)
terraform state rm <resource_address>
```

### Drift Remediation Decision Summary

| Situation | Action |
|-----------|--------|
| Tags drifted, change is unwanted | Apply via pipeline (no config change) |
| Tags drifted, external system manages them | Add `ignore_changes` for those tag keys |
| SKU changed, change is a permanent improvement | Update `.tfvars`, open PR, apply |
| SKU changed, change is temporary | Apply via pipeline to revert |
| Security setting weakened | Revert immediately; check Activity Log |
| Resource created manually, needs Terraform management | Write resource block, run import helper, reconcile plan |
| Resource drifting on auto-managed field | Add `ignore_changes` with explanatory comment |
| Drift shows destroy+recreate on stateful resource | Schedule maintenance window; do not apply unreviewed |
