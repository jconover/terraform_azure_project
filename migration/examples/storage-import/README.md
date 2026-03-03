# Worked Example: Migrating a Storage Account from Bicep to Terraform

This guide walks through importing an existing Azure Storage Account (originally deployed via Bicep) into Terraform state using the declarative `import` block (Terraform 1.5+).

## Prerequisites

- Terraform >= 1.6.0
- Azure CLI authenticated (`az login`)
- Contributor access to the target subscription
- The existing storage account's resource ID

## Step 1: Identify the Existing Resource

Query the existing storage account to capture its current configuration:

```bash
az storage account show \
  --name stlegacydata \
  --resource-group rg-legacy \
  --output json
```

Expected output (abbreviated):

```json
{
  "name": "stlegacydata",
  "resourceGroup": "rg-legacy",
  "location": "eastus2",
  "sku": {
    "name": "Standard_LRS",
    "tier": "Standard"
  },
  "kind": "StorageV2",
  "properties": {
    "minimumTlsVersion": "TLS1_2",
    "supportsHttpsTrafficOnly": true,
    "publicNetworkAccess": "Disabled",
    "allowSharedKeyAccess": false,
    "networkAcls": {
      "defaultAction": "Deny",
      "bypass": "AzureServices",
      "ipRules": [],
      "virtualNetworkRules": []
    },
    "encryption": {
      "services": {
        "blob": { "enabled": true }
      }
    },
    "blobServiceProperties": {
      "deleteRetentionPolicy": {
        "enabled": true,
        "days": 7
      },
      "containerDeleteRetentionPolicy": {
        "enabled": true,
        "days": 7
      },
      "isVersioningEnabled": false
    }
  },
  "tags": {
    "Environment": "production",
    "ManagedBy": "bicep"
  }
}
```

Record the resource ID from the output — you'll need it for the import block:

```
/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-legacy/providers/Microsoft.Storage/storageAccounts/stlegacydata
```

## Step 2: Write the Terraform Configuration

Create a Terraform configuration that matches the existing resource's settings exactly. See `main.tf` in this directory for the full example.

Key points:
- Every attribute must match the live resource, or Terraform will show a diff on the first plan.
- Use `az storage account show` output to populate variable values.
- Reference the `modules/storage-account` module to keep consistency with the rest of the project.

## Step 3: Add the Import Block

Add an `import` block to `main.tf` that tells Terraform to adopt the existing resource into state rather than creating a new one:

```hcl
import {
  to = module.migrated_storage.azurerm_storage_account.this
  id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-legacy/providers/Microsoft.Storage/storageAccounts/stlegacydata"
}
```

This is a declarative alternative to `terraform import` CLI commands. The `import` block:
- Lives in your `.tf` files alongside the resource configuration
- Is processed during `terraform plan` and `terraform apply`
- Can be code-reviewed and version-controlled

## Step 4: Run `terraform plan` to Verify Zero Changes

```bash
terraform init
terraform plan
```

Expected output when the configuration matches perfectly:

```
module.migrated_storage.azurerm_storage_account.this: Preparing import... [id=/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-legacy/providers/Microsoft.Storage/storageAccounts/stlegacydata]
module.migrated_storage.azurerm_storage_account.this: Refreshing state... [id=/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-legacy/providers/Microsoft.Storage/storageAccounts/stlegacydata]

Plan: 1 to import, 0 to add, 0 to change, 0 to destroy.
```

If the plan shows **0 to change**, you're ready to apply. If it shows changes, proceed to Step 5.

## Step 5: Handle Any Drift

Common mismatches between Bicep-deployed storage accounts and the Terraform module defaults:

| Attribute | Bicep Default | Terraform Module Default | Resolution |
|-----------|---------------|--------------------------|------------|
| `blob_soft_delete_retention_days` | 7 | 30 | Set variable to `7` to match |
| `container_soft_delete_retention_days` | 7 | 30 | Set variable to `7` to match |
| `versioning_enabled` | `false` | `true` | Set variable to `false` to match |
| `network_rules_default_action` | `"Allow"` | `"Deny"` | Set variable to match existing |
| `shared_access_key_enabled` | `true` | `false` | Set variable to match existing |
| `public_network_access_enabled` | `true` | `false` | Set variable to match existing |

Iterate on the configuration until `terraform plan` shows zero changes beyond the import.

## Step 6: Use `lifecycle { ignore_changes }` for Externally Managed Attributes

If certain attributes are managed outside Terraform (e.g., by another team's automation or Azure Policy), use `ignore_changes` to prevent Terraform from reverting them.

> **Note:** The `lifecycle` block must be added inside the module's resource definition if needed. For migration purposes, it's usually better to match the configuration exactly rather than ignoring changes.

If you find an attribute that genuinely cannot be managed by Terraform (e.g., tags set by Azure Policy), you can add it to the module:

```hcl
resource "azurerm_storage_account" "this" {
  # ... existing config ...

  lifecycle {
    ignore_changes = [
      tags["CreatedBy"],      # Set by Azure Policy
      tags["CostCenter"],     # Managed by FinOps automation
    ]
  }
}
```

## Step 7: Apply and Remove the Import Block

Once `terraform plan` shows only the import and zero changes:

```bash
terraform apply
```

Expected output:

```
module.migrated_storage.azurerm_storage_account.this: Importing... [id=/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-legacy/providers/Microsoft.Storage/storageAccounts/stlegacydata]
module.migrated_storage.azurerm_storage_account.this: Import complete [id=/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-legacy/providers/Microsoft.Storage/storageAccounts/stlegacydata]

Apply complete! Resources: 1 imported, 0 added, 0 changed, 0 destroyed.
```

After the import is in state and stable, **remove the `import` block** from `main.tf`. It is no longer needed — the resource is now tracked in Terraform state.

```bash
# Remove the import block from main.tf, then verify:
terraform plan
# Should show: No changes. Your infrastructure matches the configuration.
```

Commit the final configuration (without the import block) to version control.

## Post-Migration Checklist

- [ ] `terraform plan` shows no changes after removing the import block
- [ ] Update the `ManagedBy` tag from `bicep` to `terraform`
- [ ] Remove or archive the corresponding Bicep template
- [ ] Update any CI/CD pipelines to use Terraform instead of Bicep
- [ ] Document the migration in your team's runbook
