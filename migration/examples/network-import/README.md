# Worked Example: Migrating Networking (VNet + Subnets) from Bicep to Terraform

This guide demonstrates importing multiple related Azure networking resources — a Virtual Network, two Subnets, and a Network Security Group — from an existing Bicep deployment into Terraform state.

Multi-resource imports require careful attention to dependency ordering and consistent configuration across all related resources.

## Prerequisites

- Terraform >= 1.6.0
- Azure CLI authenticated (`az login`)
- Contributor access to the target subscription
- Resource IDs for all resources being imported

## Step 1: Identify the Existing Resources

Query each resource to capture its current configuration:

### Virtual Network

```bash
az network vnet show \
  --name vnet-legacy \
  --resource-group rg-legacy \
  --output json
```

Expected output (abbreviated):

```json
{
  "name": "vnet-legacy",
  "resourceGroup": "rg-legacy",
  "location": "eastus2",
  "addressSpace": {
    "addressPrefixes": ["10.0.0.0/16"]
  },
  "subnets": [
    {
      "name": "snet-app",
      "addressPrefix": "10.0.1.0/24",
      "networkSecurityGroup": {
        "id": "/subscriptions/.../networkSecurityGroups/nsg-legacy"
      }
    },
    {
      "name": "snet-data",
      "addressPrefix": "10.0.2.0/24",
      "serviceEndpoints": [
        { "service": "Microsoft.Storage" }
      ]
    }
  ],
  "tags": {
    "Environment": "production",
    "ManagedBy": "bicep"
  }
}
```

### Network Security Group

```bash
az network nsg show \
  --name nsg-legacy \
  --resource-group rg-legacy \
  --output json
```

Expected output (abbreviated):

```json
{
  "name": "nsg-legacy",
  "resourceGroup": "rg-legacy",
  "location": "eastus2",
  "securityRules": [
    {
      "name": "AllowHTTPS",
      "priority": 100,
      "direction": "Inbound",
      "access": "Allow",
      "protocol": "Tcp",
      "sourcePortRange": "*",
      "destinationPortRange": "443",
      "sourceAddressPrefix": "*",
      "destinationAddressPrefix": "VirtualNetwork"
    },
    {
      "name": "DenyAllInbound",
      "priority": 4096,
      "direction": "Inbound",
      "access": "Deny",
      "protocol": "*",
      "sourcePortRange": "*",
      "destinationPortRange": "*",
      "sourceAddressPrefix": "*",
      "destinationAddressPrefix": "*"
    }
  ],
  "tags": {
    "Environment": "production",
    "ManagedBy": "bicep"
  }
}
```

Record the resource IDs:

```
VNet:    /subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-legacy/providers/Microsoft.Network/virtualNetworks/vnet-legacy
Subnet1: /subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-legacy/providers/Microsoft.Network/virtualNetworks/vnet-legacy/subnets/snet-app
Subnet2: /subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-legacy/providers/Microsoft.Network/virtualNetworks/vnet-legacy/subnets/snet-data
NSG:     /subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-legacy/providers/Microsoft.Network/networkSecurityGroups/nsg-legacy
```

## Step 2: Understand Dependency Ordering

When importing multiple related resources, the order matters:

```
NSG (no dependencies)
  |
VNet (no dependencies)
  |
  +-- Subnet "snet-app" (depends on VNet + NSG)
  |
  +-- Subnet "snet-data" (depends on VNet)
```

Terraform handles dependency ordering automatically during import, but you must ensure all resources are present in the configuration. Missing a dependency causes the plan to fail.

The `import` blocks themselves don't need to be in any specific order — Terraform resolves the dependency graph from the resource configuration.

## Step 3: Write the Terraform Configuration

Create a configuration that uses the project's modules and matches every attribute of the live resources. See `main.tf` in this directory.

Key points for multi-resource imports:
- Each resource needs its own `import` block
- Module outputs can wire dependencies (e.g., NSG ID -> Subnet association)
- Match all attributes exactly to achieve a zero-diff plan

## Step 4: Run `terraform plan` to Verify

```bash
terraform init
terraform plan
```

Expected output for a clean import:

```
module.migrated_nsg.azurerm_network_security_group.this: Preparing import...
module.migrated_vnet.azurerm_virtual_network.this: Preparing import...
module.migrated_subnet_app.azurerm_subnet.this: Preparing import...
module.migrated_subnet_data.azurerm_subnet.this: Preparing import...

Plan: 4 to import, 0 to add, 0 to change, 0 to destroy.
```

## Step 5: Handle Common Pitfalls

### Subnet Delegation Changes

If a subnet has a delegation in Azure that isn't in your Terraform config, the plan will show a destructive change. Always check:

```bash
az network vnet subnet show \
  --name snet-app \
  --vnet-name vnet-legacy \
  --resource-group rg-legacy \
  --query "delegations"
```

If delegations exist, add them to the module configuration.

### NSG Rule Ordering

Azure returns security rules sorted by priority. Ensure your Terraform rules list matches the priority order from `az network nsg show`. Mismatched ordering causes unnecessary diffs.

### Address Space Modifications

If the VNet's address space was expanded after initial Bicep deployment, ensure your Terraform configuration includes all current CIDR blocks — not just the original one.

```bash
az network vnet show --name vnet-legacy --resource-group rg-legacy --query "addressSpace.addressPrefixes"
# Output: ["10.0.0.0/16"]
```

### Subnet-NSG Association

The `subnet` module creates an `azurerm_subnet_network_security_group_association` resource when `network_security_group_id` is provided. This association also needs to be imported. Add an additional import block:

```hcl
import {
  to = module.migrated_subnet_app.azurerm_subnet_network_security_group_association.this[0]
  id = "/subscriptions/.../providers/Microsoft.Network/virtualNetworks/vnet-legacy/subnets/snet-app"
}
```

## Step 6: Alternative — Using `aztfexport` for Discovery

[`aztfexport`](https://github.com/Azure/aztfexport) can auto-discover existing Azure resources and generate Terraform configuration. It's useful as a starting point but typically requires cleanup:

```bash
# Install aztfexport
go install github.com/Azure/aztfexport/cmd/aztfexport@latest

# Export a resource group (interactive mode)
aztfexport resource-group rg-legacy

# Export a single resource
aztfexport resource /subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-legacy/providers/Microsoft.Network/virtualNetworks/vnet-legacy
```

`aztfexport` generates raw `azurerm_*` resources. To use project modules instead:
1. Run `aztfexport` to discover all attributes and their current values
2. Map those attributes to the corresponding module variables
3. Write `import` blocks targeting the module's internal resources (e.g., `module.migrated_vnet.azurerm_virtual_network.this`)

## Step 7: Apply and Clean Up

```bash
terraform apply
```

Expected output:

```
module.migrated_nsg.azurerm_network_security_group.this: Importing...
module.migrated_nsg.azurerm_network_security_group.this: Import complete
module.migrated_vnet.azurerm_virtual_network.this: Importing...
module.migrated_vnet.azurerm_virtual_network.this: Import complete
module.migrated_subnet_app.azurerm_subnet.this: Importing...
module.migrated_subnet_app.azurerm_subnet.this: Import complete
module.migrated_subnet_data.azurerm_subnet.this: Importing...
module.migrated_subnet_data.azurerm_subnet.this: Import complete

Apply complete! Resources: 4 imported, 0 added, 0 changed, 0 destroyed.
```

After successful import:
1. Remove all `import` blocks from `main.tf`
2. Run `terraform plan` to confirm: `No changes. Your infrastructure matches the configuration.`
3. Commit the final configuration

## Post-Migration Checklist

- [ ] All resources show `No changes` in `terraform plan`
- [ ] Subnet-NSG associations are correctly imported
- [ ] Update `ManagedBy` tags from `bicep` to `terraform`
- [ ] Remove or archive corresponding Bicep templates
- [ ] Update CI/CD pipelines to use Terraform
- [ ] Verify network connectivity is unaffected after migration
- [ ] Document imported resource IDs in your migration log
