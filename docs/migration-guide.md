# Bicep to Terraform Migration Reference Guide

This guide covers every step of migrating Azure infrastructure management from Bicep templates to
Terraform (AzureRM provider). It is intended as a practical, day-to-day reference for engineers
performing or reviewing migration work.

---

## Table of Contents

1. [Migration Overview and Strategy](#1-migration-overview-and-strategy)
2. [When to Migrate: Bicep vs Terraform Decision Framework](#2-when-to-migrate-bicep-vs-terraform-decision-framework)
3. [Bicep-to-Terraform Construct Mapping Reference](#3-bicep-to-terraform-construct-mapping-reference)
4. [Step-by-Step Migration Workflow](#4-step-by-step-migration-workflow)
5. [Using Terraform Import Blocks (Terraform 1.5+)](#5-using-terraform-import-blocks-terraform-15)
6. [Using aztfexport for Bulk Resource Import](#6-using-aztfexport-for-bulk-resource-import)
7. [Using the import-helper.sh Script](#7-using-the-import-helpersh-script)
8. [Worked Example: Migrating a Storage Account](#8-worked-example-migrating-a-storage-account)
9. [Worked Example: Migrating a Network Stack](#9-worked-example-migrating-a-network-stack)
10. [State Management During Migration](#10-state-management-during-migration)
11. [Validation and Testing Migrated Resources](#11-validation-and-testing-migrated-resources)
12. [Parallel Run Strategy (Bicep + Terraform)](#12-parallel-run-strategy-bicep--terraform)
13. [Rollback Procedures](#13-rollback-procedures)
14. [Common Migration Pitfalls and Solutions](#14-common-migration-pitfalls-and-solutions)
15. [Migration Checklist per Resource Type](#15-migration-checklist-per-resource-type)

---

## 1. Migration Overview and Strategy

### Why Migrate

The migration from Bicep to Terraform delivers several platform-level benefits:

| Benefit | Description |
|---------|-------------|
| Multi-cloud readiness | Terraform supports AWS, GCP, and 3,000+ providers; Bicep is Azure-only |
| Ecosystem and tooling | Mature testing (Terratest, tftest), policy (OPA/Sentinel), cost estimation (Infracost), drift detection |
| Explicit state management | Plan/apply workflows, safe import of existing resources, and refactoring with confidence |
| Module registry | Public and private registries for reusable, versioned modules |
| Team velocity | Consistent HCL syntax across all infrastructure; one tool to learn |

### Phased Approach

The migration is organized into five risk-ordered phases, migrating stable foundation resources
before stateful and compute resources:

| Phase | Weeks | Resources | Risk |
|-------|-------|-----------|------|
| 1: Foundation | 1-2 | Resource Groups, VNet, Subnets, NSGs, Private Endpoints, Log Analytics | Low |
| 2: Identity and Governance | 3-4 | Managed Identities, RBAC, Azure Policy, Key Vault | Medium |
| 3: Storage and Data | 4-5 | Storage Accounts (with CMK) | Medium |
| 4: Compute | 5-6 | AKS Clusters, Node Pools | High |
| 5: Specialized | 7 | Fabric Capacity | Highest |

### Core Principle: No Dual-Management

Each Azure resource is owned by exactly one IaC tool at any point in time. A resource begins under
Bicep ownership, passes through a transitional importing state, and ends under Terraform ownership.
There is no period where both tools manage the same resource simultaneously.

### Dependency Graph

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
  +-- storage-account  (depends: vnet, key-vault, identity)
  +-- aks-cluster      (depends: vnet, identity, log-analytics)
  +-- fabric-capacity
  +-- azure-policy
```

Migrate in dependency order: foundation resources first, then resources that depend on them. Never
migrate a resource before its dependencies are stable in Terraform state.

---

## 2. When to Migrate: Bicep vs Terraform Decision Framework

### Use This Decision Tree

```
Is the resource being created new (never deployed via Bicep)?
  YES -> Create it in Terraform directly. No migration needed.
  NO  -> Continue below.

Is the resource in Phase 1 or 2 (foundation/identity)?
  YES -> Schedule for immediate migration (low risk, high dependency value).
  NO  -> Continue below.

Does the resource hold data or serve live traffic?
  YES -> Migrate during a scheduled maintenance window. Follow the High Risk process.
  NO  -> Migrate using the Standard process.
```

### Risk Classification

| Risk Level | Criteria | Examples | Migration Process |
|-----------|---------|---------|------------------|
| Low | Stateless, no data loss on recreation, no downstream dependents | Resource Groups, NSG rules | Standard |
| Medium | Stateful but recoverable, or has downstream dependents that tolerate brief disruption | Storage Accounts (soft-delete on), Key Vaults (soft-delete on), Managed Identities | Standard with extra validation |
| High | Data loss risk on recreation, significant downtime impact, complex dependency graphs | AKS clusters, databases, Fabric Capacity, RBAC policy chains | Maintenance window required |

### When NOT to Migrate Immediately

- If a Bicep module is being actively changed by another team, coordinate first.
- If a resource is in a prod environment and a maintenance window cannot be scheduled in the current
  sprint, defer to the next window.
- If the `azurerm` provider does not fully support all attributes of the resource (check with
  `aztfexport` or the provider changelog), defer until provider support is confirmed.

---

## 3. Bicep-to-Terraform Construct Mapping Reference

### Quick Reference Table

| # | Bicep Construct | Terraform Equivalent | Notes |
|---|----------------|---------------------|-------|
| 1 | `param storagePrefix string` | `variable "storage_prefix" { type = string }` | Terraform supports `validation` blocks with custom conditions |
| 2 | `var location = resourceGroup().location` | `locals { location = data.azurerm_resource_group.this.location }` | Terraform locals can reference data sources, variables, and other locals |
| 3 | `output storageId string = sa.id` | `output "storage_id" { value = azurerm_storage_account.this.id }` | Terraform supports `sensitive = true` to suppress output display |
| 4 | `resource sa 'Microsoft.Storage/storageAccounts@2023-01-01'` | `resource "azurerm_storage_account" "this" {}` | Terraform uses provider-specific resource types instead of ARM API versions |
| 5 | `module stg './storage.bicep' = {}` | `module "stg" { source = "./modules/storage" }` | Terraform `source` supports local paths, Git URLs, registries, and S3/GCS |
| 6 | `resource kv 'Microsoft.KeyVault/vaults@2023-07-01' existing` | `data "azurerm_key_vault" "this" {}` | Terraform data sources are always read-only lookups |
| 7 | `@description('The storage account name')` | `description = "The storage account name"` | Used on variables, outputs, and locals in Terraform |
| 8 | `@allowed(['Standard_LRS', 'Standard_GRS'])` | `validation { condition = contains([...], var.sku) }` | Terraform validations support regex, length checks, and custom error messages |
| 9 | `for` expression / `[for i in range(0,3)]` | `for_each` / `count` | Terraform strongly prefers `for_each` with maps/sets over `count` with indices |
| 10 | `if condition` on resource | `count = var.enabled ? 1 : 0` or `for_each` with empty map | Terraform conditional creation via count or for_each with empty collection |
| 11 | `dependsOn: [vnet]` | `depends_on = [azurerm_virtual_network.this]` | Terraform infers most dependencies automatically from resource references |
| 12 | `scope: subscription()` | `provider` alias with `subscription_id` | Terraform uses provider aliases for cross-scope deployments |
| 13 | Nested child resources | Separate `resource` blocks or `dynamic` blocks | Terraform prefers flat resource structure |
| 14 | `targetScope = 'subscription'` | `provider "azurerm" { features {} }` | Terraform scope is determined by provider configuration |
| 15 | `'${prefix}${uniqueString(rg.id)}'` | `"${var.prefix}${substr(sha256(azurerm_resource_group.this.id), 0, 13)}"` | Different quote characters; Terraform uses built-in functions |
| 16 | `@secure()` decorator | `sensitive = true` on variable | Terraform redacts sensitive values in plan/apply output and state display |
| 17 | `union()`, `intersection()` | `merge()`, `setintersection()` | Terraform has a rich function library |
| 18 | `loadTextContent('file.txt')` | `file("file.txt")` | Terraform `file()` reads at plan time; `templatefile()` supports substitution |
| 19 | `deployment().name` | `terraform.workspace` | Different concepts, similar environment-identification purpose |
| 20 | `@batchSize(1)` on loops | `parallelism` flag on `terraform apply` | Terraform controls parallelism globally, not per-resource |

### Code Example: Simple Storage Account

**Bicep:**

```bicep
@description('The name of the storage account')
param name string

@description('The Azure region')
param location string = resourceGroup().location

@description('The storage account SKU')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_ZRS'])
param skuName string = 'Standard_LRS'

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: name
  location: location
  kind: 'StorageV2'
  sku: { name: skuName }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
  }
  tags: tags
}

output storageAccountId string = storageAccount.id
```

**Terraform equivalent:**

```hcl
variable "name" {
  description = "The name of the storage account"
  type        = string
}

variable "sku_name" {
  description = "The storage account SKU"
  type        = string
  default     = "Standard_LRS"

  validation {
    condition     = contains(["Standard_LRS", "Standard_GRS", "Standard_ZRS"], var.sku_name)
    error_message = "SKU must be one of: Standard_LRS, Standard_GRS, Standard_ZRS."
  }
}

resource "azurerm_storage_account" "this" {
  name                          = var.name
  resource_group_name           = var.resource_group_name
  location                      = var.location
  account_tier                  = "Standard"
  account_replication_type      = replace(var.sku_name, "Standard_", "")
  account_kind                  = "StorageV2"
  min_tls_version               = "TLS1_2"
  https_traffic_only_enabled    = true
  public_network_access_enabled = false
  tags                          = var.tags
}

output "storage_account_id" {
  description = "The ID of the storage account"
  value       = azurerm_storage_account.this.id
}
```

Key translation notes:
- Bicep `sku.name` maps to separate `account_tier` and `account_replication_type` attributes in
  Terraform.
- Bicep `@allowed()` becomes a `validation` block.
- Bicep `properties.*` attributes are flattened to top-level attributes in Terraform.
- Bicep `camelCase` property names become `snake_case` in Terraform.

### Code Example: Conditional Resource with Loop

**Bicep:**

```bicep
param deployNsgs bool = true
param nsgConfigs array = [...]

resource nsgs 'Microsoft.Network/networkSecurityGroups@2023-11-01' = [
  for nsg in nsgConfigs: if (deployNsgs) {
    name: nsg.name
    properties: {
      securityRules: [for rule in nsg.rules: { ... }]
    }
  }
]
```

**Terraform equivalent:**

```hcl
variable "deploy_nsgs" {
  type    = bool
  default = true
}

variable "nsg_configs" {
  type = map(object({
    rules = list(object({ ... }))
  }))
}

resource "azurerm_network_security_group" "this" {
  for_each = var.deploy_nsgs ? var.nsg_configs : {}

  name                = each.key
  resource_group_name = var.resource_group_name
  location            = var.location

  dynamic "security_rule" {
    for_each = each.value.rules
    content {
      name      = security_rule.value.name
      priority  = security_rule.value.priority
      # ... other attributes
    }
  }
}
```

Key translation notes:
- Bicep `array` + `for` + `if` becomes Terraform `for_each` with a conditional empty map.
- Bicep inline nested arrays become `dynamic` blocks in Terraform.
- Terraform prefers `map(object(...))` over untyped `array` for stronger type safety.

---

## 4. Step-by-Step Migration Workflow

Follow these steps for every resource or module being migrated.

### Step 1: Inventory and Classify

Before touching any configuration:

1. List all Bicep modules and the resource types they deploy.
2. Assign a risk level (Low / Medium / High) using the criteria in Section 2.
3. Map out dependencies. A resource cannot be migrated before its dependencies are in Terraform state.
4. Record the Azure resource ID for every resource to be imported. The ID format is:

```
/subscriptions/{subscription-id}/resourceGroups/{rg-name}/providers/{provider-namespace}/{resource-type}/{resource-name}
```

### Step 2: Write the Terraform Configuration

Write a Terraform module that matches the live resource exactly. Use `az` CLI queries to capture
the current state:

```bash
az storage account show --name <name> --resource-group <rg> --output json
az network vnet show     --name <name> --resource-group <rg> --output json
az keyvault show         --name <name> --resource-group <rg> --output json
```

Populate every attribute from the live resource output. Common traps:
- Bicep and Terraform module defaults often differ. Always use the live resource values.
- Boolean attributes expressed as strings in ARM JSON may need to be expressed as `true`/`false` in HCL.
- Enum values from ARM JSON are usually direct string values in HCL (check provider docs for exact names).

### Step 3: Add Import Blocks

Add declarative `import` blocks to your `.tf` files (requires Terraform 1.5+). See Section 5 for
full syntax and examples.

### Step 4: Run terraform plan

```bash
terraform init
terraform plan
```

The plan output must show **zero changes** (beyond the import itself). If the plan shows changes to
existing attributes, resolve each one by adjusting the configuration to match the live state.

### Step 5: Apply the Import

```bash
terraform apply
```

Confirm all resources are imported successfully. The output must end with:
`N imported, 0 added, 0 changed, 0 destroyed.`

### Step 6: Remove Import Blocks and Verify

After the import is in state, remove all `import` blocks from the configuration and run plan again:

```bash
terraform plan
# Expected: No changes. Your infrastructure matches the configuration.
```

Commit the final configuration (without import blocks) to version control.

### Step 7: Update Tags and Decommission Bicep

1. Change the resource's `managed_by` tag from `bicep` to `terraform` via a standard `terraform apply`.
2. Pause the Bicep pipeline for the affected resource group.
3. Archive the Bicep source in `migration/bicep-source/`.
4. After a one-week soak period with no issues, decommission the Bicep pipeline entirely.

---

## 5. Using Terraform Import Blocks (Terraform 1.5+)

Declarative import blocks are the preferred import method. They live alongside your resource
configuration in `.tf` files, participate in the standard plan/apply workflow, and can be
code-reviewed.

### Basic Syntax

```hcl
import {
  to = <resource_address>
  id = "<azure_resource_id>"
}
```

### Single Resource Example

```hcl
import {
  to = azurerm_storage_account.this
  id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-prod/providers/Microsoft.Storage/storageAccounts/stprodapp01"
}
```

### Module-Nested Resource Example

When importing into a resource that is instantiated inside a module:

```hcl
import {
  to = module.storage.azurerm_storage_account.this
  id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-prod/providers/Microsoft.Storage/storageAccounts/stprodapp01"
}
```

### for_each Resource Example

When the resource uses `for_each`, the import target must specify the map key:

```hcl
import {
  to = azurerm_network_security_group.this["nsg-web"]
  id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-prod/providers/Microsoft.Network/networkSecurityGroups/nsg-web"
}
```

### Using -generate-config-out to Bootstrap Configuration

When migrating a resource with many attributes, Terraform can generate an initial configuration
from the live resource:

```bash
# Add a minimal import block first (resource config does NOT need to exist yet)
cat >> imports.tf << 'EOF'
import {
  to = azurerm_storage_account.generated
  id = "/subscriptions/.../storageAccounts/stprodapp01"
}
EOF

# Generate a starting configuration
terraform plan -generate-config-out=generated.tf
```

The generated file contains every attribute Terraform read from Azure. Use it as a starting point,
then refactor into your module structure. Delete `generated.tf` and replace with your final module
configuration.

### Import Block Workflow Summary

```
Write import block -> terraform plan (verify 0 changes) -> terraform apply -> remove import block -> terraform plan (verify no changes) -> commit
```

---

## 6. Using aztfexport for Bulk Resource Import

`aztfexport` auto-discovers existing Azure resources and generates Terraform configuration. It is
most useful for:

- Discovering the correct resource IDs for all resources in a resource group.
- Generating a complete attribute list when constructing Terraform config by hand would be
  prohibitively slow.
- Auditing what resources exist in a resource group before writing import blocks.

### Installation

```bash
# Using Go
go install github.com/Azure/aztfexport/cmd/aztfexport@latest

# Using Homebrew (macOS/Linux)
brew install aztfexport
```

### Common Usage Patterns

**Export an entire resource group (interactive mode):**

```bash
aztfexport resource-group rg-legacy -o ./aztfexport-output
```

The interactive mode presents a TUI allowing you to select which resources to include. Deselect
any resources you do not want in the generated output.

**Export a single resource:**

```bash
aztfexport resource \
  /subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-legacy/providers/Microsoft.Storage/storageAccounts/stlegacydata \
  -o ./aztfexport-output
```

**Non-interactive export (for scripting):**

```bash
aztfexport resource-group rg-legacy --non-interactive -o ./aztfexport-output
```

### Interpreting aztfexport Output

`aztfexport` generates three files in the output directory:

| File | Purpose |
|------|---------|
| `main.tf` | Flat `azurerm_*` resource blocks with all current attribute values |
| `provider.tf` | Provider configuration |
| `terraform.tf` | `import` blocks for each resource |

### Using aztfexport Output with Project Modules

The generated code uses flat `azurerm_*` resources, not the project's modules. To use the output
effectively:

1. Run `aztfexport` to get the complete attribute list and current values.
2. Map the flat attributes to the corresponding module variables.
3. Write `import` blocks that target the module's internal resource paths (e.g.,
   `module.storage.azurerm_storage_account.this`).
4. Discard the `aztfexport` generated `main.tf` once you have the attribute values you need.

### Caution: Do Not Use aztfexport Output Directly in Production

The flat generated configuration bypasses project module conventions, naming standards, and
variable validation. Always treat `aztfexport` output as a discovery tool, not a final
configuration source.

---

## 7. Using the import-helper.sh Script

The `scripts/import-helper.sh` script wraps the legacy `terraform import` CLI command with
pre-import and post-import plan comparison. It is useful for one-off imports and troubleshooting
when declarative import blocks are not practical.

### Location

```
/home/justi/projects/terraform_azure_project/scripts/import-helper.sh
```

### Usage

```bash
./scripts/import-helper.sh <resource_address> <resource_id>
```

### Example

```bash
./scripts/import-helper.sh \
  azurerm_storage_account.main \
  "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-prod/providers/Microsoft.Storage/storageAccounts/stprodapp01"
```

### What the Script Does

1. Runs `terraform plan` before the import and captures the output.
2. Runs `terraform import` to bring the resource into state.
3. Runs `terraform plan` again after the import.
4. Diffs the before and after plan outputs so you can see exactly what changed.

### When to Use the Script vs Import Blocks

| Scenario | Recommended Tool |
|----------|-----------------|
| New migration work | Declarative `import` blocks (Section 5) |
| One-off state corrections | `import-helper.sh` |
| Resource type does not support import blocks | `import-helper.sh` |
| Bulk imports (many resources) | `aztfexport` + import blocks |
| Debugging a failed import | `import-helper.sh` (easier to iterate) |

### After Using the Script

After `import-helper.sh` completes, the resource is in Terraform state via the CLI import path.
Add a corresponding `import` block to your `.tf` files if you want the import to be declarative
and reviewable. Then run `terraform plan` to confirm zero changes, and commit.

---

## 8. Worked Example: Migrating a Storage Account

This example migrates `stlegacydata` from `rg-legacy`, originally deployed via Bicep, into
Terraform state.

### Prerequisites

- Terraform >= 1.6.0
- Azure CLI authenticated (`az login`)
- Contributor access to the target subscription

### Step 1: Query the Existing Resource

```bash
az storage account show \
  --name stlegacydata \
  --resource-group rg-legacy \
  --output json
```

Capture the configuration:

```json
{
  "name": "stlegacydata",
  "resourceGroup": "rg-legacy",
  "location": "eastus2",
  "sku": { "name": "Standard_LRS", "tier": "Standard" },
  "kind": "StorageV2",
  "properties": {
    "minimumTlsVersion": "TLS1_2",
    "supportsHttpsTrafficOnly": true,
    "publicNetworkAccess": "Disabled",
    "allowSharedKeyAccess": false,
    "networkAcls": {
      "defaultAction": "Deny",
      "bypass": "AzureServices"
    },
    "blobServiceProperties": {
      "deleteRetentionPolicy": { "enabled": true, "days": 7 },
      "containerDeleteRetentionPolicy": { "enabled": true, "days": 7 },
      "isVersioningEnabled": false
    }
  },
  "tags": { "Environment": "production", "ManagedBy": "bicep" }
}
```

Record the full resource ID:

```
/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-legacy/providers/Microsoft.Storage/storageAccounts/stlegacydata
```

### Step 2: Write the Terraform Configuration

Create `main.tf` matching the live resource exactly:

```hcl
module "migrated_storage" {
  source = "../../modules/storage-account"

  name                = "stlegacydata"
  resource_group_name = "rg-legacy"
  location            = "eastus2"
  account_replication_type = "LRS"
  account_tier             = "Standard"
  account_kind             = "StorageV2"

  # Match live values, not module defaults
  min_tls_version               = "TLS1_2"
  https_traffic_only_enabled    = true
  public_network_access_enabled = false
  shared_access_key_enabled     = false

  blob_soft_delete_retention_days      = 7   # Live value, not module default of 30
  container_soft_delete_retention_days = 7   # Live value, not module default of 30
  versioning_enabled                   = false  # Live value, not module default of true

  network_rules = {
    default_action = "Deny"
    bypass         = ["AzureServices"]
    ip_rules       = []
    virtual_network_subnet_ids = []
  }

  tags = {
    Environment = "production"
    ManagedBy   = "bicep"  # Keep as-is until import is verified
  }
}
```

### Step 3: Add the Import Block

```hcl
import {
  to = module.migrated_storage.azurerm_storage_account.this
  id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-legacy/providers/Microsoft.Storage/storageAccounts/stlegacydata"
}
```

### Step 4: Run terraform plan

```bash
terraform init
terraform plan
```

Expected output:

```
module.migrated_storage.azurerm_storage_account.this: Preparing import...
module.migrated_storage.azurerm_storage_account.this: Refreshing state...

Plan: 1 to import, 0 to add, 0 to change, 0 to destroy.
```

If the plan shows changes, see the drift resolution table below.

### Common Drift Between Bicep and Terraform Module Defaults

| Attribute | Bicep Default | Terraform Module Default | Resolution |
|-----------|---------------|--------------------------|------------|
| `blob_soft_delete_retention_days` | 7 | 30 | Set variable to `7` |
| `container_soft_delete_retention_days` | 7 | 30 | Set variable to `7` |
| `versioning_enabled` | `false` | `true` | Set variable to `false` |
| `network_rules_default_action` | `"Allow"` | `"Deny"` | Set variable to match existing |
| `shared_access_key_enabled` | `true` | `false` | Set variable to match existing |
| `public_network_access_enabled` | `true` | `false` | Set variable to match existing |

### Step 5: Apply and Remove Import Block

```bash
terraform apply
```

Expected:
```
Apply complete! Resources: 1 imported, 0 added, 0 changed, 0 destroyed.
```

Remove the `import` block from `main.tf`, then confirm:

```bash
terraform plan
# No changes. Your infrastructure matches the configuration.
```

### Step 6: Update the ManagedBy Tag

```hcl
tags = {
  Environment = "production"
  ManagedBy   = "terraform"  # Update after successful import
}
```

```bash
terraform apply
```

### Post-Migration Checklist

- [ ] `terraform plan` shows no changes after removing the import block
- [ ] `ManagedBy` tag updated from `bicep` to `terraform`
- [ ] Bicep template removed or archived in `migration/bicep-source/`
- [ ] CI/CD pipeline updated to use Terraform
- [ ] Migration recorded in team runbook

---

## 9. Worked Example: Migrating a Network Stack

This example migrates a Virtual Network (`vnet-legacy`), two Subnets (`snet-app`, `snet-data`),
and a Network Security Group (`nsg-legacy`) from `rg-legacy` as a single coordinated import.

### Step 1: Query All Resources

```bash
az network vnet show --name vnet-legacy --resource-group rg-legacy --output json
az network nsg show  --name nsg-legacy  --resource-group rg-legacy --output json
az network vnet subnet show --name snet-app  --vnet-name vnet-legacy --resource-group rg-legacy --output json
az network vnet subnet show --name snet-data --vnet-name vnet-legacy --resource-group rg-legacy --output json
```

Record all four resource IDs:

```
VNet:    /subscriptions/00000000.../resourceGroups/rg-legacy/providers/Microsoft.Network/virtualNetworks/vnet-legacy
Subnet1: /subscriptions/00000000.../resourceGroups/rg-legacy/providers/Microsoft.Network/virtualNetworks/vnet-legacy/subnets/snet-app
Subnet2: /subscriptions/00000000.../resourceGroups/rg-legacy/providers/Microsoft.Network/virtualNetworks/vnet-legacy/subnets/snet-data
NSG:     /subscriptions/00000000.../resourceGroups/rg-legacy/providers/Microsoft.Network/networkSecurityGroups/nsg-legacy
```

### Step 2: Understand Dependency Ordering

```
NSG (no dependencies)
  |
VNet (no dependencies)
  |
  +-- snet-app  (depends on VNet + NSG)
  +-- snet-data (depends on VNet)
```

Terraform resolves the dependency graph from resource references automatically. However, all
resources must be present in the configuration. Missing a dependency causes the plan to fail.

The `import` blocks themselves do not need to be in any specific order.

### Step 3: Write the Configuration

```hcl
module "migrated_nsg" {
  source = "../../modules/network-security-group"

  name                = "nsg-legacy"
  resource_group_name = "rg-legacy"
  location            = "eastus2"

  security_rules = [
    {
      name                       = "AllowHTTPS"
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "443"
      source_address_prefix      = "*"
      destination_address_prefix = "VirtualNetwork"
    },
    {
      name                       = "DenyAllInbound"
      priority                   = 4096
      direction                  = "Inbound"
      access                     = "Deny"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    }
  ]

  tags = { Environment = "production", ManagedBy = "bicep" }
}

module "migrated_vnet" {
  source = "../../modules/virtual-network"

  name                = "vnet-legacy"
  resource_group_name = "rg-legacy"
  location            = "eastus2"
  address_space       = ["10.0.0.0/16"]

  tags = { Environment = "production", ManagedBy = "bicep" }
}

module "migrated_subnet_app" {
  source = "../../modules/subnet"

  name                 = "snet-app"
  resource_group_name  = "rg-legacy"
  virtual_network_name = module.migrated_vnet.name
  address_prefixes     = ["10.0.1.0/24"]
  network_security_group_id = module.migrated_nsg.id
}

module "migrated_subnet_data" {
  source = "../../modules/subnet"

  name                 = "snet-data"
  resource_group_name  = "rg-legacy"
  virtual_network_name = module.migrated_vnet.name
  address_prefixes     = ["10.0.2.0/24"]

  service_endpoints = ["Microsoft.Storage"]
}
```

### Step 4: Add Import Blocks

```hcl
import {
  to = module.migrated_nsg.azurerm_network_security_group.this
  id = "/subscriptions/00000000.../resourceGroups/rg-legacy/providers/Microsoft.Network/networkSecurityGroups/nsg-legacy"
}

import {
  to = module.migrated_vnet.azurerm_virtual_network.this
  id = "/subscriptions/00000000.../resourceGroups/rg-legacy/providers/Microsoft.Network/virtualNetworks/vnet-legacy"
}

import {
  to = module.migrated_subnet_app.azurerm_subnet.this
  id = "/subscriptions/00000000.../resourceGroups/rg-legacy/providers/Microsoft.Network/virtualNetworks/vnet-legacy/subnets/snet-app"
}

import {
  to = module.migrated_subnet_data.azurerm_subnet.this
  id = "/subscriptions/00000000.../resourceGroups/rg-legacy/providers/Microsoft.Network/virtualNetworks/vnet-legacy/subnets/snet-data"
}

# If the subnet module creates a subnet-NSG association resource, import that too:
import {
  to = module.migrated_subnet_app.azurerm_subnet_network_security_group_association.this[0]
  id = "/subscriptions/00000000.../resourceGroups/rg-legacy/providers/Microsoft.Network/virtualNetworks/vnet-legacy/subnets/snet-app"
}
```

### Step 5: Run Plan and Apply

```bash
terraform init
terraform plan
```

Expected:
```
Plan: 4 to import, 0 to add, 0 to change, 0 to destroy.
```

```bash
terraform apply
```

Expected:
```
Apply complete! Resources: 4 imported, 0 added, 0 changed, 0 destroyed.
```

### Network-Specific Pitfalls

**Subnet delegations:** If a subnet has a delegation in Azure that is not in your Terraform config,
the plan shows a destructive change. Always check:

```bash
az network vnet subnet show \
  --name snet-app --vnet-name vnet-legacy --resource-group rg-legacy \
  --query "delegations"
```

Add any delegations to the module configuration.

**NSG rule ordering:** Azure returns security rules sorted by priority. Match the priority order
from `az network nsg show` exactly to avoid unnecessary diffs.

**Expanded address space:** If the VNet's address space was expanded after initial Bicep deployment,
include all current CIDR blocks in the Terraform config:

```bash
az network vnet show --name vnet-legacy --resource-group rg-legacy --query "addressSpace.addressPrefixes"
```

### Post-Migration Checklist

- [ ] All resources show no changes in `terraform plan`
- [ ] Subnet-NSG associations are correctly imported
- [ ] `ManagedBy` tags updated from `bicep` to `terraform`
- [ ] Bicep templates archived in `migration/bicep-source/`
- [ ] CI/CD pipelines updated
- [ ] Network connectivity verified as unaffected (ping test, application health check)
- [ ] Imported resource IDs recorded in migration log

---

## 10. State Management During Migration

### Remote State Backend

All environments must use a remote state backend with locking. The Azure Storage backend is standard
for this project:

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "stterraformstate"
    container_name       = "tfstate"
    key                  = "prod/terraform.tfstate"
  }
}
```

State locking prevents concurrent runs from corrupting state during imports.

### Separate State Files per Environment

Each environment maintains an independent state file. Migrations are sequenced: dev -> staging ->
production.

```
environments/
  dev/
    terraform.tfstate        # Dev environment (migrate first)
  staging/
    terraform.tfstate        # Staging (migrate second)
  prod/
    terraform.tfstate        # Production (migrate last)
```

### State File Backup Before Import

Before any import batch, back up the current state:

```bash
# Download current state
terraform state pull > terraform.tfstate.backup.$(date +%Y%m%d-%H%M%S)

# Store backup safely (not in version control)
cp terraform.tfstate.backup.* /secure/backup/location/
```

### Inspecting State

```bash
# List all resources currently in state
terraform state list

# Show full details of a specific resource
terraform state show azurerm_storage_account.this

# Show details of a module's resources
terraform state show module.storage.azurerm_storage_account.this
```

### Moving Resources in State

When restructuring into modules after an import, use `terraform state mv`:

```bash
# Move a top-level resource into a module
terraform state mv \
  azurerm_storage_account.this \
  module.storage.azurerm_storage_account.this
```

Always run `terraform plan` after any state move to confirm zero drift.

### Removing Resources from State (Without Deleting in Azure)

If a resource was imported incorrectly or needs to be removed from Terraform management:

```bash
terraform state rm module.storage.azurerm_storage_account.this
```

This removes the resource from Terraform state without touching the actual Azure resource.

### Handling Attribute Drift with lifecycle Blocks

When Bicep-deployed resources have attribute values that differ from Terraform module defaults,
use `lifecycle { ignore_changes }` as a temporary bridge:

```hcl
resource "azurerm_storage_account" "this" {
  # ... config ...

  lifecycle {
    ignore_changes = [
      tags["createdBy"],  # Set by Azure Policy, not manageable via Terraform
    ]
  }
}
```

These are temporary. Track every `ignore_changes` entry and remove them systematically as each
difference is resolved. Migration is not complete until all `lifecycle { ignore_changes }` blocks
are gone (except those justified by architecture, e.g., policy-managed tags).

---

## 11. Validation and Testing Migrated Resources

### Tier 1: Plan Validation (Zero Changes)

The primary migration success criterion is a clean `terraform plan`:

```bash
terraform plan
# Must output: No changes. Your infrastructure matches the configuration.
```

Any change shown in the plan after import is a bug that must be fixed before proceeding.

### Tier 2: Smoke Test — Small Reversible Change

After achieving a zero-change plan, prove that Terraform can manage the resource end-to-end:

```bash
# 1. Add a non-destructive tag change in the configuration
tags = {
  managed_by     = "terraform"
  migration_test = "true"   # Add this
}

# 2. Apply and verify
terraform apply
az resource show --ids <resource-id> --query "tags"
# Confirm migration_test=true appears in Azure Portal or CLI output

# 3. Remove the test tag and apply again to clean up
```

If the tag change applies and reverts cleanly, Terraform has full management of the resource.

### Tier 3: Functional Validation

For each resource type, run functional tests to confirm the migrated resource behaves correctly:

**Storage Account:**

```bash
# Test blob access
az storage blob list \
  --account-name stlegacydata \
  --container-name mycontainer \
  --auth-mode login

# Test connectivity from application
curl -I https://stlegacydata.blob.core.windows.net/mycontainer/
```

**Virtual Network / Subnets:**

```bash
# Verify existing VMs/pods can still communicate
# Check effective NSG rules
az network nic show-effective-nsg --name <nic-name> --resource-group <rg>
```

**Key Vault:**

```bash
# Test secret retrieval
az keyvault secret show --vault-name <vault-name> --name <secret-name>
```

**AKS Cluster:**

```bash
# Get credentials and check node health
az aks get-credentials --name <cluster-name> --resource-group <rg>
kubectl get nodes
kubectl get pods --all-namespaces
```

### Tier 4: CI/CD Pipeline Validation

Update CI/CD pipelines to run `terraform plan` on every pull request targeting a migrated
environment. A failing plan on PR indicates a drift or configuration error that must be resolved
before merge.

```yaml
# Example Azure DevOps pipeline step
- task: TerraformCLI@2
  displayName: "Terraform Plan"
  inputs:
    command: plan
    workingDirectory: environments/$(environment)
    environmentServiceName: $(serviceConnection)
```

---

## 12. Parallel Run Strategy (Bicep + Terraform)

### Coexistence Rules

During migration, both tools coexist under strict ownership boundaries:

| Rule | Description |
|------|-------------|
| New resources | Always created in Terraform, never in Bicep |
| Existing unmigrated resources | Remain under Bicep until their scheduled migration phase |
| No dual-management | Each resource is owned by exactly one tool at any time |
| Migrating resources | Tagged `managed_by = "importing"` during the transition window |

### Resource Ownership Tags

All resources carry a tag indicating their current IaC owner:

```hcl
# Not yet migrated (still Bicep-managed)
tags = { managed_by = "bicep" }

# Currently being migrated (transitional, may last hours to days)
tags = { managed_by = "importing" }

# Successfully imported and verified
tags = { managed_by = "terraform" }
```

Use these tags to audit migration progress at any time:

```bash
# Count resources by IaC owner across the subscription
az resource list --subscription <sub-id> \
  --query "[].tags.managed_by" \
  --output tsv | sort | uniq -c
```

### Pipeline Configuration During Parallel Run

| Pipeline | State | Scope |
|----------|-------|-------|
| Bicep (existing) | Active -> Paused -> Decommissioned | Manages resources not yet migrated |
| Terraform (new) | Active and growing | Manages migrated resources + all new resources |

Both pipelines run in the same CI/CD system. During a resource's migration phase:

1. Pause the Bicep pipeline for that specific resource group (do not run `az deployment` for it).
2. Complete the Terraform import and validation.
3. Decommission the Bicep pipeline step for that resource group.

Never decommission the Bicep pipeline for a resource group until Terraform shows a zero-change
plan for all resources in that group.

### Handling Conflicts

If a Bicep pipeline runs on a resource that is simultaneously being imported into Terraform:

1. Stop the Bicep run immediately if possible.
2. Run `terraform plan` to check for drift.
3. If drift is detected, run `terraform refresh` and then `terraform plan` again.
4. Apply any corrections through Terraform.
5. Establish a Bicep pipeline freeze for that resource group before resuming migration.

---

## 13. Rollback Procedures

### Before You Start: Preparation

1. Back up the current Terraform state file (see Section 10).
2. Ensure the Bicep pipeline for the affected resource group is paused but not decommissioned.
3. Confirm the Bicep source templates are accessible in `migration/bicep-source/`.

### Rollback Scenario 1: Import Produces Unexpected Changes

If `terraform apply` applies an import but subsequent `terraform plan` shows unintended changes:

```bash
# 1. Remove the incorrectly imported resource from state
terraform state rm <resource_address>

# 2. Restore state from backup if other resources were affected
terraform state push terraform.tfstate.backup.YYYYMMDD-HHMMSS

# 3. Re-run the Bicep pipeline to ensure the resource matches its original state
# (The Bicep pipeline was kept paused, not decommissioned, for this reason)

# 4. Investigate the configuration mismatch and fix before retrying
```

### Rollback Scenario 2: Accidental Resource Recreation

If `terraform apply` destroys and recreates a resource (a plan review failure):

1. Immediately stop the pipeline if possible.
2. Assess damage: run `az resource show` to confirm the resource's current state.
3. If the resource is stateless or soft-deleted, recreate via Bicep pipeline.
4. If the resource holds data (e.g., storage), assess data recovery options:
   - Storage Account: Check soft-delete / point-in-time restore
   - Key Vault: Check soft-delete (90-day purge protection)
5. Remove the incorrectly managed resource from Terraform state.
6. Re-import using the corrected configuration.

### Rollback Scenario 3: Full Environment Rollback

If Terraform management of an entire resource group needs to be rolled back to Bicep:

```bash
# 1. Remove all resources for the environment from Terraform state
# (Does NOT delete resources in Azure)
terraform state rm module.resource_group
terraform state rm module.vnet
# ... repeat for all resources

# 2. Re-activate the Bicep pipeline for the resource group
# 3. Run az deployment to re-sync Bicep state

# 4. Investigate root cause before retrying migration
```

### Rollback Decision Tree

```
Was the Bicep pipeline decommissioned?
  NO  -> Roll back via Terraform state rm + re-activate Bicep pipeline
  YES -> Must fix forward via Terraform (Bicep source is archived but pipeline is gone)

Is data at risk?
  YES -> Engage data team immediately; check soft-delete / backup before any apply
  NO  -> Proceed with standard rollback steps
```

---

## 14. Common Migration Pitfalls and Solutions

### Pitfall 1: Plan Shows Changes After Import

**Symptom:** `terraform plan` shows attribute changes after a successful import.

**Causes and solutions:**

| Cause | Solution |
|-------|----------|
| Module default differs from live value | Set the variable explicitly to match the live value |
| Bicep used a different API version that set different defaults | Query live resource, match all attributes |
| Boolean/enum mismatch (e.g., `"Enabled"` vs `true`) | Check provider documentation for the correct HCL representation |
| Computed attribute not expressible in config | Add to `ignore_changes` temporarily; document the exception |

### Pitfall 2: Wrong Resource ID Format

**Symptom:** `terraform import` or `import` block fails with "resource not found".

**Cause:** Azure resource IDs are case-sensitive in some positions and require exact provider
namespace casing.

**Solution:** Use `aztfexport` or `az resource show` to get the canonical resource ID:

```bash
az resource show \
  --name stlegacydata \
  --resource-group rg-legacy \
  --resource-type "Microsoft.Storage/storageAccounts" \
  --query "id" \
  --output tsv
```

### Pitfall 3: Missing Child Resources

**Symptom:** After importing a parent resource, plan shows creation of child resources that
already exist in Azure.

**Cause:** Child resources (containers, secrets, subnets) must be imported separately.

**Solution:** Import each child resource individually. Use `aztfexport` to discover all child
resources associated with a parent.

**Example for storage containers:**

```hcl
import {
  to = module.storage.azurerm_storage_container.this["mycontainer"]
  id = "https://stlegacydata.blob.core.windows.net/mycontainer"
}
```

### Pitfall 4: Subnet-NSG Association Not Imported

**Symptom:** Plan shows creating an `azurerm_subnet_network_security_group_association` that
already exists.

**Cause:** The association is a separate Terraform resource from both the subnet and the NSG.

**Solution:** Import the association using the subnet resource ID (which serves as the
association's ID in the Azure provider):

```hcl
import {
  to = module.subnet.azurerm_subnet_network_security_group_association.this[0]
  id = "/subscriptions/.../virtualNetworks/vnet-legacy/subnets/snet-app"
}
```

### Pitfall 5: for_each Key Mismatch

**Symptom:** Plan shows destroy-and-create for resources that should be imported in-place.

**Cause:** The key used in the Terraform `for_each` map does not match the key expected by the
import target address.

**Solution:** Ensure the map keys in your `for_each` variable match the resource names in Azure
exactly, including case. Adjust the import target address to use the correct key:

```hcl
# Correct: key matches the Azure resource name
import {
  to = azurerm_network_security_group.this["nsg-web"]  # key = "nsg-web"
  id = ".../networkSecurityGroups/nsg-web"
}
```

### Pitfall 6: Provider Version Incompatibility

**Symptom:** `terraform init` fails, or imported resources show attributes that the provider does
not recognize.

**Cause:** The `azurerm` provider version in use does not support all attributes of the resource
being imported.

**Solution:** Check the AzureRM provider changelog for the resource type. Pin a specific provider
version and test in dev:

```hcl
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.90"  # Pin to a tested version
    }
  }
}
```

### Pitfall 7: Permission Gaps

**Symptom:** `terraform plan` or `apply` fails with authorization errors for certain resource types.

**Cause:** The Terraform service principal lacks permissions that the Bicep pipeline's service
principal had.

**Solution:** Audit the Bicep pipeline SPN permissions and mirror them to the Terraform SPN:

```bash
# List current role assignments for the Bicep SPN
az role assignment list --assignee <bicep-spn-object-id> --output table

# Assign the same roles to the Terraform SPN
az role assignment create \
  --assignee <terraform-spn-object-id> \
  --role "Contributor" \
  --scope /subscriptions/<sub-id>
```

### Pitfall 8: Fabric Capacity Provider Support

**Symptom:** Fabric Capacity attributes are not recognized by the current `azurerm` provider version.

**Cause:** Fabric Capacity is a newer Azure service; provider support may lag.

**Solution:** Before migrating Fabric Capacity, verify that the target `azurerm` provider version
fully supports all Fabric Capacity attributes:

```bash
# Check provider changelog
curl https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/CHANGELOG.md | grep -i fabric
```

If support is incomplete, defer migration until the required provider version is available.

---

## 15. Migration Checklist per Resource Type

### Resource Group

```
Prerequisites:
  [ ] Subscription ID confirmed
  [ ] Resource group resource ID captured

Import:
  [ ] import block added to main.tf
  [ ] terraform plan shows 0 to change
  [ ] terraform apply succeeds
  [ ] import block removed; terraform plan confirms no changes

Post-migration:
  [ ] managed_by tag updated to "terraform"
  [ ] Bicep template archived
```

### Virtual Network and Subnets

```
Prerequisites:
  [ ] All subnet IDs captured (including delegations, service endpoints)
  [ ] Associated NSG IDs captured
  [ ] VNet address space verified (may have expanded since initial deployment)

Import:
  [ ] NSG imported first (no dependencies)
  [ ] VNet imported
  [ ] Each subnet imported individually
  [ ] Subnet-NSG association resources imported
  [ ] terraform plan shows 0 to change across all resources

Validation:
  [ ] Network connectivity test passed
  [ ] Effective NSG rules verified
  [ ] No route table changes detected

Post-migration:
  [ ] All managed_by tags updated
  [ ] Bicep templates archived
```

### Network Security Group

```
Prerequisites:
  [ ] All security rules listed and sorted by priority
  [ ] Default rules (Azure-managed) excluded from config

Import:
  [ ] NSG resource imported
  [ ] All custom security rules verified in plan
  [ ] terraform plan shows 0 to change

Post-migration:
  [ ] managed_by tag updated
  [ ] Verify associated subnets still show correct NSG in portal
```

### Key Vault

```
Prerequisites:
  [ ] Soft-delete status confirmed as enabled (critical safety check)
  [ ] Access policies listed; note which are managed by Terraform vs external processes
  [ ] Private endpoint (if any) identified for separate import

Import:
  [ ] Key Vault resource imported
  [ ] Access policies imported or reconciled
  [ ] Private endpoint imported if applicable
  [ ] terraform plan shows 0 to change

Validation:
  [ ] Secret retrieval tested from an authorized identity
  [ ] Key operations tested if keys are in scope

Post-migration:
  [ ] managed_by tag updated
  [ ] Bicep template archived
  [ ] Secrets remain in-place (never recreated during import)
```

### Managed Identity and RBAC

```
Prerequisites:
  [ ] Client ID and principal ID recorded (used by downstream resources)
  [ ] All role assignments listed (scope + role + principal)

Import:
  [ ] Managed identity imported
  [ ] Each role assignment imported individually using composite ID:
      {scope}/providers/Microsoft.Authorization/roleAssignments/{id}
  [ ] terraform plan shows 0 to change

Post-migration:
  [ ] managed_by tag updated
  [ ] Downstream resources verified still use correct identity
```

### Storage Account

```
Prerequisites:
  [ ] Soft-delete enabled for blobs and containers (verify before any operation)
  [ ] All containers listed
  [ ] Network rules captured (IP rules, VNet rules, service endpoints)
  [ ] CMK configuration captured if applicable
  [ ] Lifecycle management policies captured

Import:
  [ ] Storage account resource imported
  [ ] Containers imported individually
  [ ] Lifecycle policy imported
  [ ] CMK association imported if applicable
  [ ] terraform plan shows 0 to change

Drift resolution:
  [ ] blob_soft_delete_retention_days matched to live value
  [ ] container_soft_delete_retention_days matched to live value
  [ ] versioning_enabled matched to live value
  [ ] shared_access_key_enabled matched to live value
  [ ] public_network_access_enabled matched to live value

Validation:
  [ ] Blob read/write test passed from authorized identity
  [ ] Application connectivity verified

Post-migration:
  [ ] managed_by tag updated
  [ ] Bicep template archived
```

### AKS Cluster

```
Prerequisites:
  [ ] Maintenance window scheduled
  [ ] Node pool details captured (count, SKU, version)
  [ ] Diagnostics settings captured
  [ ] Add-ons list captured
  [ ] OIDC and workload identity settings captured

Import (during maintenance window only):
  [ ] AKS cluster resource imported
  [ ] Node pool(s) imported
  [ ] Diagnostics settings imported
  [ ] terraform plan shows 0 to change (verify carefully — any change to node pools
      may trigger node pool recreation)
  [ ] terraform apply succeeds with 0 added, 0 changed, 0 destroyed

Validation:
  [ ] kubectl get nodes shows all nodes Ready
  [ ] All workloads healthy post-import
  [ ] kubectl get pods --all-namespaces: no unexpected restarts

Post-migration:
  [ ] managed_by tag updated
  [ ] Bicep template archived
  [ ] Maintenance window closed
```

### Azure Policy

```
Prerequisites:
  [ ] Policy assignment IDs captured at all scopes (subscription, management group, resource group)
  [ ] Policy exemptions listed
  [ ] Initiative (policy set) assignments listed separately from individual policy assignments

Import:
  [ ] Each policy assignment imported
  [ ] Policy exemptions imported
  [ ] terraform plan shows 0 to change

Post-migration:
  [ ] Compliance state verified in Azure Policy portal
  [ ] managed_by tag updated where applicable
```

### Fabric Capacity

```
Prerequisites:
  [ ] azurerm provider version verified to support all Fabric Capacity attributes
  [ ] Capacity name, SKU, and admin list captured
  [ ] Confirm no active workloads will be interrupted

Import:
  [ ] Fabric Capacity resource imported
  [ ] terraform plan shows 0 to change

Validation:
  [ ] Fabric workloads accessible post-import
  [ ] Capacity state shows "Active" in Azure Portal

Post-migration:
  [ ] managed_by tag updated
  [ ] Bicep template archived
```

---

## Final Migration Success Criteria

Migration is complete when ALL of the following are satisfied across all environments:

- [ ] Every Azure resource carries the tag `managed_by = "terraform"`
- [ ] `terraform plan` shows zero changes for dev, staging, and production
- [ ] All Bicep pipelines are decommissioned and source archived in `migration/bicep-source/`
- [ ] No `lifecycle { ignore_changes }` blocks remain (except architecturally justified exceptions, documented)
- [ ] Terraform state is stored in Azure Storage remote backend with locking enabled
- [ ] CI/CD pipelines run `terraform plan` on PR and `terraform apply` on merge to main
- [ ] Team members can independently create, review, and apply Terraform changes
- [ ] Runbooks cover: state recovery, provider upgrades, and module versioning
