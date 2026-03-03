# Bicep to Terraform Migration Plan

## 1. Executive Summary

This document defines the strategy for migrating Azure infrastructure management from Bicep templates to Terraform (AzureRM provider). The migration delivers:

- **Multi-cloud readiness** - Terraform supports AWS, GCP, and 3,000+ providers; Bicep is Azure-only
- **Ecosystem & tooling** - Mature testing (Terratest, tftest), policy (OPA/Sentinel), cost estimation (Infracost), and drift detection
- **State management** - Explicit state tracking enables plan/apply workflows, import of existing resources, and safe refactoring
- **Module registry** - Public and private registries for reusable, versioned modules
- **Team velocity** - Consistent HCL syntax across all infrastructure; single tool to learn

The migration follows a phased, risk-ordered approach. Bicep and Terraform coexist during transition with clear resource ownership boundaries. No resources are dual-managed.

---

## 2. Assessment Phase

### 2.1 Inventory All Bicep Modules

Catalog every Bicep template, noting resource types, complexity, inter-module dependencies, and data risk.

| # | Bicep Module | Resource Types | Complexity | Dependencies | Risk Level |
|---|-------------|---------------|-----------|-------------|-----------|
| 1 | `networking.bicep` | VNet, Subnet, NSG, NSG Rules | Medium | None (foundation) | Low |
| 2 | `resource-group.bicep` | Resource Group | Low | None | Low |
| 3 | `key-vault.bicep` | Key Vault, Access Policies, Secrets | Medium | Resource Group, VNet | Medium |
| 4 | `managed-identity.bicep` | User Assigned Identity, Role Assignments | Low | Resource Group | Medium |
| 5 | `storage-account.bicep` | Storage Account, Containers, Lifecycle Policies | Medium | Resource Group, VNet, Key Vault (CMK) | Medium |
| 6 | `aks-cluster.bicep` | AKS Cluster, Node Pools, Diagnostics | High | VNet, Identity, Log Analytics | High |
| 7 | `fabric-capacity.bicep` | Fabric Capacity | Low | Resource Group | High |

### 2.2 Classification Criteria

| Risk Level | Criteria | Examples |
|-----------|---------|---------|
| **Low** | Stateless, no data loss on recreation, no downstream dependents | Resource Groups, NSG rules, naming conventions |
| **Medium** | Stateful but recoverable, or has downstream dependents that can tolerate brief disruption | Storage Accounts (with soft-delete), Key Vaults (with soft-delete), Managed Identities |
| **High** | Data loss risk on recreation, significant downtime impact, complex dependency graphs | AKS clusters, databases, Fabric Capacity, RBAC policy chains |

### 2.3 Dependency Graph

```
resource-group
  +-- virtual-network
  |     +-- subnet
  |     +-- network-security-group
  |     +-- private-endpoint
  +-- log-analytics
  +-- key-vault
  +-- managed-identity
  |     +-- rbac-assignment
  +-- storage-account (depends: vnet, key-vault, identity)
  +-- aks-cluster (depends: vnet, identity, log-analytics)
  +-- fabric-capacity
  +-- azure-policy
```

---

## 3. Migration Sequencing

### Phase 1: Foundation (Weeks 1-2) - Low Risk

Migrate foundational resources that have no data and serve as dependencies for everything else.

| Module | Import Complexity | Notes |
|--------|------------------|-------|
| `naming` | N/A | Logic-only module, no resources to import |
| `resource-group` | Simple | Single resource, one `import` block |
| `virtual-network` | Simple | Import VNet, verify address space |
| `subnet` | Simple | Import each subnet by resource ID |
| `network-security-group` | Medium | Import NSG + all rules |
| `private-endpoint` | Simple | Import endpoint + NIC |
| `log-analytics` | Simple | Import workspace, verify retention |

### Phase 2: Identity & Governance (Weeks 3-4) - Medium Risk

Migrate identity resources that compute and data layers depend on.

| Module | Import Complexity | Notes |
|--------|------------------|-------|
| `managed-identity` | Simple | Import identity, note client/principal IDs |
| `rbac-assignment` | Medium | Import each role assignment by scope+principal |
| `azure-policy` | Medium | Import policy assignments, verify exemptions |
| `key-vault` | Medium | Import vault + access policies; secrets remain in-place |

### Phase 3: Storage & Data (Weeks 4-5) - Medium Risk

Migrate stateful storage resources. Requires careful state import to avoid recreation.

| Module | Import Complexity | Notes |
|--------|------------------|-------|
| `storage-account` | High | Import account + containers + lifecycle rules + CMK config |

### Phase 4: Compute (Weeks 5-6) - High Risk

Migrate compute workloads. Requires maintenance windows for AKS.

| Module | Import Complexity | Notes |
|--------|------------------|-------|
| `aks-cluster` | High | Import cluster + node pools + diagnostics; schedule during maintenance window |

### Phase 5: Specialized (Week 7) - Highest Risk

Migrate resources with newest provider support.

| Module | Import Complexity | Notes |
|--------|------------------|-------|
| `fabric-capacity` | Medium | Newer provider resource; verify `azurerm` provider version supports all attributes |

---

## 4. State Import Strategy

### 4.1 Import Blocks vs CLI Import

**Preferred: `import` blocks (Terraform 1.5+)**

```hcl
import {
  to = azurerm_storage_account.this
  id = "/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Storage/storageAccounts/{name}"
}
```

Advantages:
- Declarative, reviewable in code
- Part of `terraform plan` workflow
- Can generate config with `terraform plan -generate-config-out=generated.tf`

**Fallback: `terraform import` CLI**

Use only when import blocks are unsupported for a specific resource type or when doing one-off corrections.

### 4.2 Bulk Discovery with aztfexport

Use `aztfexport` to discover and generate initial Terraform configurations from existing Azure resources:

```bash
# Export an entire resource group
aztfexport resource-group myResourceGroup -o ./import-output

# Export a specific resource
aztfexport resource /subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Storage/storageAccounts/{name}
```

The generated code serves as a reference; hand-written modular code should be the final target.

### 4.3 State File Management

Maintain separate state files during migration:

```
environments/
  dev/
    terraform.tfstate          # Migrated resources (Terraform-managed)
  staging/
    terraform.tfstate
  prod/
    terraform.tfstate
```

Each environment migrates independently: dev first, then staging, then production.

### 4.4 Handling Attribute Drift

Bicep and Terraform may set different defaults for optional attributes. Use `lifecycle` blocks to prevent unnecessary changes during import stabilization:

```hcl
resource "azurerm_storage_account" "this" {
  # ... config ...

  lifecycle {
    ignore_changes = [
      # Temporarily ignore attributes where Bicep defaults differ
      # Remove these once terraform plan shows zero unintended changes
      tags["createdBy"],
    ]
  }
}
```

Remove all `ignore_changes` entries before declaring migration complete.

### 4.5 Rollback Approach

1. Keep Bicep pipelines **active but paused** until Terraform fully manages each resource
2. After import, run `terraform plan` - it must show **zero changes**
3. Make one small, reversible Terraform change (e.g., add a tag) and apply it
4. Verify the change appears in Azure Portal
5. Only then decommission the Bicep pipeline for that resource group
6. Maintain Bicep source in a `migration/bicep-source/` archive directory for reference

---

## 5. Parallel Run Period

### 5.1 Coexistence Rules

During migration, Bicep and Terraform coexist under strict ownership rules:

- **New resources**: Always created in Terraform
- **Existing resources**: Remain in Bicep until their migration phase
- **No dual-management**: Each resource is owned by exactly one IaC tool at any time

### 5.2 Resource Tagging

Tag every resource to indicate its IaC owner:

```
managed_by = "bicep"      # Not yet migrated
managed_by = "terraform"  # Successfully imported and verified
managed_by = "importing"  # Currently being migrated (transitional)
```

### 5.3 Pipeline Configuration

| Pipeline | State | Purpose |
|----------|-------|---------|
| Bicep (existing) | Active -> Paused -> Decommissioned | Manages non-migrated resources |
| Terraform (new) | Active | Manages migrated + new resources |

Both pipelines run in the same CI/CD system (Azure DevOps). The Terraform pipeline uses the existing `pipelines/` directory structure.

---

## 6. Milestones & Timeline

| Week | Milestone | Deliverables | Exit Criteria |
|------|----------|-------------|---------------|
| 1-2 | Foundation migration | VNet, subnets, NSGs, RGs imported; `terraform plan` clean | Zero-change plan for all foundation resources |
| 3-4 | Identity & governance migration | Identities, RBAC, policies, Key Vault imported | Zero-change plan; existing workloads unaffected |
| 4-5 | Storage migration | Storage accounts + containers imported with CMK intact | Zero-change plan; blob access verified |
| 5-6 | Compute migration | AKS clusters imported during maintenance window | Zero-change plan; workloads healthy post-import |
| 7 | Specialized migration + Bicep freeze | Fabric Capacity imported; no new Bicep development | All resources show `managed_by = "terraform"` |
| 8 | Terraform cutover | Bicep pipelines decommissioned | Terraform is sole IaC tool |
| 9-10 | Cleanup & validation | Remove `lifecycle` ignores, archive Bicep source, team training | Success criteria met (see Section 8) |

---

## 7. Risk Mitigations

| # | Risk | Likelihood | Impact | Mitigation |
|---|------|-----------|--------|-----------|
| 1 | **State corruption** during import | Low | High | Use remote state with locking (Azure Storage backend); backup state before each import batch |
| 2 | **Accidental resource recreation** | Medium | High | Always run `terraform plan` before `apply`; review plan output for destroy/create actions; use `-target` for isolated imports |
| 3 | **Downtime during AKS migration** | Low | High | Schedule during maintenance window; import only (no config changes); verify node pool health immediately |
| 4 | **Permission gaps** in Terraform SPN | Medium | Medium | Audit Bicep pipeline SPN permissions; mirror to Terraform SPN; test in dev environment first |
| 5 | **Provider version incompatibility** | Low | Medium | Pin `azurerm` provider version; test newer versions in dev before promoting |
| 6 | **Team unfamiliarity with Terraform** | Medium | Medium | Conduct training sessions in Weeks 1-2; pair programming during initial migrations; document patterns in `CLAUDE.md` |
| 7 | **Bicep attribute defaults differ from Terraform** | High | Low | Use `lifecycle { ignore_changes }` temporarily; systematically resolve each difference |
| 8 | **Import ID format errors** | Medium | Low | Use `aztfexport` to discover correct resource IDs; maintain an ID reference document |

---

## 8. Success Criteria

Migration is complete when ALL of the following are true:

- [ ] Every Azure resource is managed by Terraform (`managed_by = "terraform"` tag)
- [ ] `terraform plan` shows **zero changes** for all environments (dev, staging, production)
- [ ] All Bicep pipelines are decommissioned and archived
- [ ] No `lifecycle { ignore_changes }` blocks remain (unless architecturally justified)
- [ ] Terraform state is stored in a remote backend with locking enabled
- [ ] CI/CD pipelines run `terraform plan` on PR and `terraform apply` on merge
- [ ] Team members can independently create, review, and apply Terraform changes
- [ ] Runbook documents cover: state recovery, provider upgrades, and module versioning
- [ ] Migration source Bicep files archived in `migration/bicep-source/` for reference
