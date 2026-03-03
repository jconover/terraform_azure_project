<!-- BEGIN_TF_DOCS -->
# Naming Convention Module

Generates consistent, Azure-compliant resource names following organizational standards.

## Pattern

`{project}-{environment}-{location_short}-{resource_abbreviation}`

Special handling for globally-unique names:
- **Storage Accounts**: No hyphens, max 24 chars, lowercase alphanumeric only, includes hash suffix
- **Key Vaults**: Max 24 chars, alphanumeric and hyphens

## Usage

```hcl
module "naming" {
  source = "../../modules/naming"

  project     = "platform"
  environment = "dev"
  location    = "eastus2"
  unique_seed = var.subscription_id
}

resource "azurerm_resource_group" "main" {
  name     = module.naming.resource_group
  location = var.location
}
```

## Location Abbreviations

| Region | Abbreviation |
|--------|-------------|
| eastus | eus |
| eastus2 | eus2 |
| westus2 | wus2 |
| centralus | cus |
| northeurope | neu |
| westeurope | weu |
| uksouth | uks |

## Resource Abbreviations

| Resource | Abbreviation |
|----------|-------------|
| Resource Group | rg |
| Virtual Network | vnet |
| Subnet | snet |
| NSG | nsg |
| Storage Account | st |
| Key Vault | kv |
| AKS Cluster | aks |
| Log Analytics | law |
| Managed Identity | id |
| Private Endpoint | pe |
| Fabric Capacity | fc |
<!-- END_TF_DOCS -->
