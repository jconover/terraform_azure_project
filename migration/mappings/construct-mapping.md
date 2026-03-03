# Bicep to Terraform Construct Mapping

This document provides a comprehensive side-by-side mapping of Bicep language constructs to their Terraform (HCL) equivalents.

## Construct Reference Table

| # | Bicep Construct | Terraform Equivalent | Notes |
|---|----------------|---------------------|-------|
| 1 | `param storagePrefix string` | `variable "storage_prefix" { type = string }` | Terraform supports `validation` blocks with custom conditions |
| 2 | `var location = resourceGroup().location` | `locals { location = data.azurerm_resource_group.this.location }` | Terraform locals can reference data sources, variables, and other locals |
| 3 | `output storageId string = sa.id` | `output "storage_id" { value = azurerm_storage_account.this.id }` | Terraform supports `sensitive = true` to suppress output display |
| 4 | `resource sa 'Microsoft.Storage/storageAccounts@2023-01-01'` | `resource "azurerm_storage_account" "this" {}` | Terraform uses provider-specific resource types instead of ARM API versions |
| 5 | `module stg './storage.bicep' = {}` | `module "stg" { source = "./modules/storage" }` | Terraform `source` supports local paths, Git URLs, registries, and S3/GCS |
| 6 | `resource kv 'Microsoft.KeyVault/vaults@2023-07-01' existing` | `data "azurerm_key_vault" "this" {}` | Terraform data sources are always read-only lookups |
| 7 | `@description('The storage account name')` | `description = "The storage account name"` | Used on variables, outputs, and locals in Terraform |
| 8 | `@allowed(['Standard_LRS', 'Standard_GRS'])` | `validation { condition = contains(["Standard_LRS", "Standard_GRS"], var.sku) }` | Terraform validations support regex, length checks, and custom error messages |
| 9 | `for` expression / `[for i in range(0,3)]` | `for_each` / `count` | Terraform strongly prefers `for_each` with maps/sets over `count` with indices |
| 10 | `if condition` on resource | `count = var.enabled ? 1 : 0` or `for_each` conditional | Terraform conditional creation via count or for_each with empty collection |
| 11 | `dependsOn: [vnet]` | `depends_on = [azurerm_virtual_network.this]` | Terraform infers most dependencies automatically from resource references |
| 12 | `scope: subscription()` | `provider` alias with `subscription_id` | Terraform uses provider aliases for cross-scope deployments |
| 13 | Nested child resources | Separate `resource` blocks or `dynamic` blocks | Terraform prefers flat resource structure; nested resources are rare |
| 14 | `targetScope = 'subscription'` | `provider "azurerm" { features {} }` | Terraform scope is determined by provider configuration, not template-level setting |
| 15 | `'${storagePrefix}${uniqueString(resourceGroup().id)}'` | `"${var.storage_prefix}${substr(sha256(azurerm_resource_group.this.id), 0, 13)}"` | Different quote characters; Terraform uses built-in functions for unique strings |
| 16 | `@secure()` decorator | `sensitive = true` on variable | Terraform redacts sensitive values in plan/apply output and state display |
| 17 | `union()`, `intersection()` | `merge()`, `setintersection()` | Terraform has a rich function library: `merge`, `concat`, `flatten`, `lookup`, etc. |
| 18 | `loadTextContent('file.txt')` | `file("file.txt")` | Terraform `file()` reads at plan time; `templatefile()` supports variable substitution |
| 19 | `deployment().name` | `terraform.workspace` | Different concepts but serve similar environment-identification purposes |
| 20 | `@batchSize(1)` on loops | `parallelism` flag on `terraform apply` | Terraform controls parallelism globally, not per-resource |

---

## Code Examples

### Example 1: Simple Storage Account

**Bicep:**

```bicep
// storage-account.bicep
@description('The name of the storage account')
param name string

@description('The Azure region')
param location string = resourceGroup().location

@description('The storage account SKU')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_ZRS'
])
param skuName string = 'Standard_LRS'

@description('Resource tags')
param tags object = {}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: name
  location: location
  kind: 'StorageV2'
  sku: {
    name: skuName
  }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
  }
  tags: tags
}

output storageAccountId string = storageAccount.id
output primaryBlobEndpoint string = storageAccount.properties.primaryEndpoints.blob
```

**Terraform:**

```hcl
# variables.tf
variable "name" {
  description = "The name of the storage account"
  type        = string
}

variable "location" {
  description = "The Azure region"
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

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}

# main.tf
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

# outputs.tf
output "storage_account_id" {
  description = "The ID of the storage account"
  value       = azurerm_storage_account.this.id
}

output "primary_blob_endpoint" {
  description = "The primary blob endpoint"
  value       = azurerm_storage_account.this.primary_blob_endpoint
}
```

**Key differences:**
- Bicep `sku.name` maps to separate `account_tier` and `account_replication_type` in Terraform
- Bicep `@allowed()` becomes a `validation` block with custom error messages
- Bicep `object` type becomes `map(string)` for stricter typing
- Bicep `properties` are flattened to top-level attributes in Terraform

---

### Example 2: Parameterized Module Call

**Bicep:**

```bicep
// main.bicep
param environment string
param location string = 'eastus2'

module storageModule './modules/storage-account.bicep' = {
  name: 'storage-${environment}'
  scope: resourceGroup('rg-${environment}')
  params: {
    name: 'st${environment}app01'
    location: location
    skuName: environment == 'prod' ? 'Standard_GRS' : 'Standard_LRS'
    tags: {
      environment: environment
      managed_by: 'bicep'
    }
  }
}

output storageId string = storageModule.outputs.storageAccountId
```

**Terraform:**

```hcl
# variables.tf
variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus2"
}

# main.tf
module "storage" {
  source = "./modules/storage-account"

  name                = "st${var.environment}app01"
  resource_group_name = "rg-${var.environment}"
  location            = var.location
  sku_name            = var.environment == "prod" ? "Standard_GRS" : "Standard_LRS"

  tags = {
    environment = var.environment
    managed_by  = "terraform"
  }
}

# outputs.tf
output "storage_id" {
  description = "The storage account ID"
  value       = module.storage.storage_account_id
}
```

**Key differences:**
- Bicep `scope: resourceGroup()` becomes an explicit `resource_group_name` parameter in Terraform
- Bicep `params:` block becomes direct attribute assignments in Terraform `module` block
- Bicep `module.outputs.x` becomes `module.x` in Terraform (no `.outputs` accessor)
- Terraform `source` attribute replaces Bicep file path reference

---

### Example 3: Conditional Resource with Loop

**Bicep:**

```bicep
// nsgs.bicep
param location string = resourceGroup().location
param deployNsgs bool = true

param nsgConfigs array = [
  {
    name: 'nsg-web'
    rules: [
      {
        name: 'AllowHTTPS'
        priority: 100
        direction: 'Inbound'
        access: 'Allow'
        protocol: 'Tcp'
        destinationPortRange: '443'
        sourceAddressPrefix: 'Internet'
        destinationAddressPrefix: 'VirtualNetwork'
      }
    ]
  }
  {
    name: 'nsg-app'
    rules: [
      {
        name: 'AllowAppPort'
        priority: 100
        direction: 'Inbound'
        access: 'Allow'
        protocol: 'Tcp'
        destinationPortRange: '8080'
        sourceAddressPrefix: 'VirtualNetwork'
        destinationAddressPrefix: 'VirtualNetwork'
      }
    ]
  }
]

resource nsgs 'Microsoft.Network/networkSecurityGroups@2023-11-01' = [
  for nsg in nsgConfigs: if (deployNsgs) {
    name: nsg.name
    location: location
    properties: {
      securityRules: [
        for rule in nsg.rules: {
          name: rule.name
          properties: {
            priority: rule.priority
            direction: rule.direction
            access: rule.access
            protocol: rule.protocol
            destinationPortRange: rule.destinationPortRange
            sourceAddressPrefix: rule.sourceAddressPrefix
            destinationAddressPrefix: rule.destinationAddressPrefix
            sourcePortRange: '*'
          }
        }
      ]
    }
  }
]

output nsgIds array = [for (nsg, i) in nsgConfigs: nsgs[i].id]
```

**Terraform:**

```hcl
# variables.tf
variable "location" {
  description = "Azure region"
  type        = string
}

variable "deploy_nsgs" {
  description = "Whether to deploy NSGs"
  type        = bool
  default     = true
}

variable "nsg_configs" {
  description = "NSG configurations"
  type = map(object({
    rules = list(object({
      name                       = string
      priority                   = number
      direction                  = string
      access                     = string
      protocol                   = string
      destination_port_range     = string
      source_address_prefix      = string
      destination_address_prefix = string
    }))
  }))
  default = {
    nsg-web = {
      rules = [{
        name                       = "AllowHTTPS"
        priority                   = 100
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        destination_port_range     = "443"
        source_address_prefix      = "Internet"
        destination_address_prefix = "VirtualNetwork"
      }]
    }
    nsg-app = {
      rules = [{
        name                       = "AllowAppPort"
        priority                   = 100
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        destination_port_range     = "8080"
        source_address_prefix      = "VirtualNetwork"
        destination_address_prefix = "VirtualNetwork"
      }]
    }
  }
}

# main.tf
resource "azurerm_network_security_group" "this" {
  for_each = var.deploy_nsgs ? var.nsg_configs : {}

  name                = each.key
  location            = var.location
  resource_group_name = var.resource_group_name

  dynamic "security_rule" {
    for_each = each.value.rules

    content {
      name                       = security_rule.value.name
      priority                   = security_rule.value.priority
      direction                  = security_rule.value.direction
      access                     = security_rule.value.access
      protocol                   = security_rule.value.protocol
      destination_port_range     = security_rule.value.destination_port_range
      source_address_prefix      = security_rule.value.source_address_prefix
      destination_address_prefix = security_rule.value.destination_address_prefix
      source_port_range          = "*"
    }
  }
}

# outputs.tf
output "nsg_ids" {
  description = "Map of NSG names to IDs"
  value       = { for k, v in azurerm_network_security_group.this : k => v.id }
}
```

**Key differences:**
- Bicep `array` + `for` + `if` becomes Terraform `for_each` with conditional empty map
- Bicep inline `securityRules` array becomes a `dynamic` block in Terraform
- Bicep array output becomes a map output in Terraform (preferred for `for_each` consumers)
- Terraform uses `map(object(...))` instead of Bicep's untyped `array` for stronger type safety
- Bicep `camelCase` property names become `snake_case` in Terraform
