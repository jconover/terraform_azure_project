# Module Usage Guide

This guide covers every module in the `modules/` directory: its purpose, inputs, outputs, usage examples, dependencies, and common patterns. It also shows how to compose all modules together for a complete environment.

---

## Table of Contents

1. [Overview and Conventions](#overview-and-conventions)
2. [Module Dependency Graph](#module-dependency-graph)
3. [Module Reference](#module-reference)
   - [naming](#naming)
   - [resource-group](#resource-group)
   - [log-analytics](#log-analytics)
   - [managed-identity](#managed-identity)
   - [virtual-network](#virtual-network)
   - [subnet](#subnet)
   - [network-security-group](#network-security-group)
   - [private-endpoint](#private-endpoint)
   - [key-vault](#key-vault)
   - [storage-account](#storage-account)
   - [aks-cluster](#aks-cluster)
   - [rbac-assignment](#rbac-assignment)
   - [azure-policy](#azure-policy)
   - [fabric-capacity](#fabric-capacity)
4. [Composing Modules for a Complete Environment](#composing-modules-for-a-complete-environment)
5. [Complete End-to-End Example](#complete-end-to-end-example)
6. [Best Practices for Module Consumption](#best-practices-for-module-consumption)

---

## Overview and Conventions

All modules follow these conventions:

- **Naming**: Every module accepts a `name` variable rather than constructing names internally. Use the `naming` module to generate consistent, CAF-aligned names and pass them in.
- **Tags**: Every module accepts a `tags = map(string)` variable defaulting to `{}`. Always pass a standard tag map.
- **Diagnostics**: Modules that support it accept `log_analytics_workspace_id`. Passing an empty string (`""`, the default) disables diagnostic settings. Passing a workspace ID automatically creates the diagnostic setting resource.
- **Network isolation**: Service modules (Key Vault, Storage Account) default to `public_network_access_enabled = false` and `network_rules_default_action = "Deny"`. You must explicitly allow access via subnet service endpoints, private endpoints, or IP rules.
- **RBAC over access policies**: Key Vault defaults to `enable_rbac_authorization = true`. Do not use legacy access policies.

Module source paths use local relative paths in this repo:

```hcl
module "example" {
  source = "../modules/example"
  ...
}
```

---

## Module Dependency Graph

The graph below shows which modules must be created before others. Arrows point from dependency to dependent.

```
                    ┌──────────┐
                    │  naming  │
                    └────┬─────┘
                         │  (provides names to all modules)
                ┌────────┴────────┐
                ▼                 ▼
        ┌──────────────┐  ┌──────────────┐
        │resource-group│  │log-analytics │
        └──────┬───────┘  └──────┬───────┘
               │                 │
       ┌───────┴──────────┐      │ (workspace ID passed to
       ▼                  ▼      │  all other modules)
┌──────────────┐  ┌──────────────────┐
│virtual-network│ │managed-identity  │
└──────┬───────┘  └──────────────────┘
       │                              │
       ▼                              ▼
┌──────────┐                  ┌────────────────┐
│  subnet  │                  │rbac-assignment │
└────┬─────┘                  └────────────────┘
     │
     ├────────────────────┐
     ▼                    ▼
┌─────────────────┐  ┌──────────────┐
│network-security │  │private-      │
│     -group      │  │  endpoint    │
└─────────────────┘  └──────────────┘
          │
    ┌─────┴──────────────┐
    ▼                    ▼                    ▼
┌───────────┐  ┌───────────────┐  ┌─────────────────┐
│ key-vault │  │storage-account│  │  aks-cluster    │
└───────────┘  └───────────────┘  └─────────────────┘

┌──────────────┐   ┌─────────────────┐
│ azure-policy │   │ fabric-capacity │
└──────────────┘   └─────────────────┘
 (standalone,        (standalone,
  subscription-       resource-group
  scoped)             dependent)
```

**Recommended creation order:**

1. `naming` (no dependencies)
2. `resource-group` (no dependencies)
3. `log-analytics` (depends on resource-group)
4. `managed-identity` (depends on resource-group)
5. `virtual-network` (depends on resource-group)
6. `network-security-group` (depends on resource-group)
7. `subnet` (depends on virtual-network, optionally NSG)
8. `key-vault` (depends on resource-group)
9. `storage-account` (depends on resource-group)
10. `private-endpoint` (depends on subnet, key-vault or storage-account)
11. `aks-cluster` (depends on resource-group, subnet, managed-identity)
12. `rbac-assignment` (depends on managed-identity principal IDs and resource IDs)
13. `azure-policy` (depends on subscription data source)
14. `fabric-capacity` (depends on resource-group)

Terraform resolves this automatically through implicit dependencies when you pass outputs between modules (e.g., `resource_group_name = module.resource_group.name`). Explicit `depends_on` is only needed when a module consumes a resource created by another module in a non-obvious way (such as RBAC assignments that must exist before a cluster can pull images).

---

## Module Reference

---

### naming

**Path**: `modules/naming`

#### Purpose

Generates consistent, Azure Cloud Adoption Framework (CAF)-aligned resource names for every resource type in this project. This module is purely a `locals`-only module — it creates no Azure resources and has no provider requirements.

Use this module once per environment stack and pass its outputs as the `name` argument to every other module. This eliminates ad hoc string construction across your codebase and ensures all names conform to Azure length/character constraints automatically.

Key behaviors:
- Constructs a `base_name` of the form `{project}-{environment}-{location_short}`.
- Appends an optional `suffix` for distinguishing multiple instances of the same resource type.
- For **storage accounts**: strips hyphens, lowercases everything, appends a 6-character hash derived from `unique_seed`, and truncates to 24 characters (Azure's global-uniqueness constraint).
- For **Key Vaults**: truncates to 24 characters (Azure limit).
- Validates that `project`, `environment`, and `location` conform to allowed values before any resource is created.

#### Inputs

| Variable | Type | Required | Default | Description |
|---|---|---|---|---|
| `project` | `string` | Yes | — | Project name. 2–10 chars, lowercase alphanumeric and hyphens, must start with a letter. |
| `environment` | `string` | Yes | — | One of `dev`, `staging`, `prod`. |
| `location` | `string` | Yes | — | Azure region (e.g. `eastus2`). Must be in the supported list. |
| `suffix` | `string` | No | `""` | Optional suffix appended to names (e.g., `"001"` for a second instance). |
| `unique_seed` | `string` | No | `""` | Seed for the globally-unique hash used in storage account names. Use the subscription ID. |

#### Outputs

| Output | Description | Example value |
|---|---|---|
| `base_name` | `{project}-{env}-{location_short}` | `platform-prod-eus2` |
| `location_short` | Abbreviated region code | `eus2` |
| `resource_group` | Resource group name | `platform-prod-eus2-rg` |
| `virtual_network` | VNet name | `platform-prod-eus2-vnet` |
| `subnet` | Subnet name | `platform-prod-eus2-snet` |
| `network_security_group` | NSG name | `platform-prod-eus2-nsg` |
| `public_ip` | Public IP name | `platform-prod-eus2-pip` |
| `private_endpoint` | Private endpoint name | `platform-prod-eus2-pe` |
| `key_vault` | Key Vault name (≤24 chars) | `platform-prod-eus2-kv` |
| `storage_account` | Storage account name (≤24 chars, no hyphens) | `platformprodeus2stabcd12` |
| `aks_cluster` | AKS cluster name | `platform-prod-eus2-aks` |
| `log_analytics_workspace` | Log Analytics workspace name | `platform-prod-eus2-law` |
| `managed_identity` | Managed identity name | `platform-prod-eus2-id` |
| `fabric_capacity` | Fabric capacity name | `platform-prod-eus2-fc` |

#### Usage Examples

**Minimal:**

```hcl
module "naming" {
  source = "../modules/naming"

  project     = "platform"
  environment = "dev"
  location    = "eastus2"
}
```

**Production-grade (with unique seed for globally unique storage names):**

```hcl
module "naming" {
  source = "../modules/naming"

  project     = "platform"
  environment = "prod"
  location    = "eastus2"
  suffix      = "001"
  unique_seed = data.azurerm_subscription.current.subscription_id
}

# Use outputs in all downstream modules:
module "resource_group" {
  source   = "../modules/resource-group"
  name     = module.naming.resource_group     # "platform-prod-eus2-rg-001"
  location = "eastus2"
  tags     = local.common_tags
}

module "storage_account" {
  source              = "../modules/storage-account"
  name                = module.naming.storage_account  # globally unique, no hyphens
  resource_group_name = module.resource_group.name
  location            = "eastus2"
  tags                = local.common_tags
}
```

#### Dependencies

None. This module creates no resources and has no provider dependencies.

#### Gotchas

- The `environment` variable only accepts `dev`, `staging`, `prod`. Any other value causes a validation error at `terraform validate` time, before any API calls.
- Always provide `unique_seed` (typically the subscription ID) when deploying to multiple environments or subscriptions to guarantee storage account name uniqueness across Azure's global namespace.
- The `suffix` is appended to all names uniformly. If you need two storage accounts with different suffixes, instantiate the `naming` module twice with different `suffix` values.
- Location must be spelled exactly as Azure accepts it (e.g., `eastus2`, not `East US 2`).

---

### resource-group

**Path**: `modules/resource-group`

#### Purpose

Creates an Azure Resource Group. Almost every other module depends on a resource group existing first. This module wraps the single `azurerm_resource_group` resource with input validation and a `prevent_destroy` lifecycle flag for production use.

#### Inputs

| Variable | Type | Required | Default | Description |
|---|---|---|---|---|
| `name` | `string` | Yes | — | Resource group name. 1–90 chars, alphanumeric, underscores, hyphens, periods, parentheses. |
| `location` | `string` | Yes | — | Azure region. Must be in the supported list. |
| `tags` | `map(string)` | No | `{}` | Tags to apply. |
| `prevent_destroy` | `bool` | No | `false` | Reserved for future lifecycle guard. Set to `true` in production after initial provisioning. |

#### Outputs

| Output | Description |
|---|---|
| `id` | Full resource group ARM ID |
| `name` | Resource group name |
| `location` | Resource group location |

#### Usage Examples

**Minimal:**

```hcl
module "resource_group" {
  source   = "../modules/resource-group"
  name     = "platform-dev-eus2-rg"
  location = "eastus2"
}
```

**Production-grade:**

```hcl
module "resource_group" {
  source   = "../modules/resource-group"
  name     = module.naming.resource_group
  location = var.location
  tags     = merge(local.common_tags, { criticality = "high" })
}
```

#### Dependencies

None. This is the root dependency for all other modules.

#### Gotchas

- The `prevent_destroy` variable is declared but does not yet wire into the `lifecycle` block dynamically (Terraform does not support dynamic lifecycle attributes). Add a manual `prevent_destroy = true` lifecycle block in your root module for production resource groups.
- Resource group names are case-insensitive in Azure but Terraform treats them as case-sensitive strings. Use the output `module.resource_group.name` consistently rather than re-constructing the string.
- Deleting a resource group destroys all resources inside it, including those not managed by Terraform. Never delete production resource groups manually.

---

### log-analytics

**Path**: `modules/log-analytics`

#### Purpose

Creates an Azure Log Analytics Workspace. This is the central observability hub: all other modules that support diagnostics accept this workspace's ID. Deploy this module early — it has no dependencies other than the resource group and enables diagnostic settings for every downstream module.

#### Inputs

| Variable | Type | Required | Default | Description |
|---|---|---|---|---|
| `name` | `string` | Yes | — | Workspace name. |
| `resource_group_name` | `string` | Yes | — | Resource group to deploy into. |
| `location` | `string` | Yes | — | Azure region. |
| `sku` | `string` | No | `"PerGB2018"` | Pricing SKU. One of: `Free`, `PerNode`, `Premium`, `Standard`, `Standalone`, `Unlimited`, `CapacityReservation`, `PerGB2018`. |
| `retention_in_days` | `number` | No | `30` | Log retention in days. Must be between 30 and 730. |
| `daily_quota_gb` | `number` | No | `-1` | Daily ingestion cap in GB. `-1` means unlimited. |
| `tags` | `map(string)` | No | `{}` | Tags to apply. |

#### Outputs

| Output | Description |
|---|---|
| `id` | ARM resource ID of the workspace |
| `name` | Workspace name |
| `workspace_id` | Customer/workspace GUID (used by agents and integrations) |
| `primary_shared_key` | Primary shared key (sensitive) |
| `resource_group_name` | Resource group name |

#### Usage Examples

**Minimal:**

```hcl
module "log_analytics" {
  source              = "../modules/log-analytics"
  name                = "platform-dev-eus2-law"
  resource_group_name = module.resource_group.name
  location            = var.location
}
```

**Production-grade (extended retention, ingestion cap):**

```hcl
module "log_analytics" {
  source              = "../modules/log-analytics"
  name                = module.naming.log_analytics_workspace
  resource_group_name = module.resource_group.name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = 365
  daily_quota_gb      = 10
  tags                = local.common_tags
}
```

#### Dependencies

- `resource-group` (provides `resource_group_name` and implicitly the location)

#### Gotchas

- Set `daily_quota_gb` in non-production environments to prevent runaway log ingestion costs. A noisy application or a misconfigured diagnostic setting can ingest gigabytes per day.
- The `primary_shared_key` output is marked `sensitive`. It will not appear in plan output, but it is stored in state. Treat state files as secrets.
- Changing the `sku` from `Free` to `PerGB2018` requires destroying and recreating the workspace. Plan this before initial deployment.
- `retention_in_days` below 30 is rejected by the validation rule. Azure's minimum retention is 30 days for the `PerGB2018` SKU.

---

### managed-identity

**Path**: `modules/managed-identity`

#### Purpose

Creates an Azure User-Assigned Managed Identity. Managed identities provide a credential-free authentication mechanism for Azure resources (AKS kubelet, storage access, Key Vault access, etc.). Create identities here, then wire their `principal_id` into `rbac-assignment` to grant permissions.

The module currently only creates `UserAssigned` identities. The `type = "SystemAssigned"` option is declared in the variable for future use but does not create a resource (system-assigned identities are created as part of the resource they attach to, such as AKS or a VM).

#### Inputs

| Variable | Type | Required | Default | Description |
|---|---|---|---|---|
| `name` | `string` | Yes | — | Identity name. |
| `resource_group_name` | `string` | Yes | — | Resource group to deploy into. |
| `location` | `string` | Yes | — | Azure region. |
| `type` | `string` | No | `"UserAssigned"` | One of `UserAssigned` or `SystemAssigned`. Only `UserAssigned` creates a resource. |
| `tags` | `map(string)` | No | `{}` | Tags to apply. |

#### Outputs

| Output | Description |
|---|---|
| `id` | ARM resource ID of the identity |
| `principal_id` | Service principal object ID (use in RBAC assignments) |
| `client_id` | Application/client ID (use in workload identity annotations) |
| `tenant_id` | Azure AD tenant ID |
| `name` | Identity name |

All outputs use `try(..., null)` so they return `null` rather than error when `type = "SystemAssigned"` is passed.

#### Usage Examples

**Minimal (AKS control plane identity):**

```hcl
module "aks_identity" {
  source              = "../modules/managed-identity"
  name                = "platform-dev-eus2-id"
  resource_group_name = module.resource_group.name
  location            = var.location
}
```

**Production-grade (separate identities per workload):**

```hcl
module "aks_control_plane_identity" {
  source              = "../modules/managed-identity"
  name                = "${module.naming.managed_identity}-aks"
  resource_group_name = module.resource_group.name
  location            = var.location
  tags                = merge(local.common_tags, { workload = "aks-control-plane" })
}

module "storage_identity" {
  source              = "../modules/managed-identity"
  name                = "${module.naming.managed_identity}-storage"
  resource_group_name = module.resource_group.name
  location            = var.location
  tags                = merge(local.common_tags, { workload = "storage-cmk" })
}
```

#### Dependencies

- `resource-group`

#### Gotchas

- Always create separate identities for different workloads (AKS, storage CMK, application workloads). Sharing one identity across roles violates least-privilege.
- The `principal_id` is used in RBAC assignments. There can be a propagation delay of up to 2 minutes after identity creation before the principal appears in Azure AD. Use `depends_on` in `rbac-assignment` if you hit `PrincipalNotFound` errors.
- For AKS workload identity, you also need the `client_id` output to configure the `serviceAccountAnnotations` in your Kubernetes manifests.

---

### virtual-network

**Path**: `modules/virtual-network`

#### Purpose

Creates an Azure Virtual Network (VNet). The VNet is the network boundary for all other network resources. Subnets, NSGs, and private endpoints all live inside a VNet. Optionally creates a diagnostic setting if a Log Analytics workspace ID is provided.

#### Inputs

| Variable | Type | Required | Default | Description |
|---|---|---|---|---|
| `name` | `string` | Yes | — | VNet name. |
| `resource_group_name` | `string` | Yes | — | Resource group to deploy into. |
| `location` | `string` | Yes | — | Azure region. |
| `address_space` | `list(string)` | Yes | — | One or more CIDR blocks. At least one required. |
| `dns_servers` | `list(string)` | No | `[]` | Custom DNS server IPs. Empty uses Azure-provided DNS. |
| `tags` | `map(string)` | No | `{}` | Tags to apply. |
| `log_analytics_workspace_id` | `string` | No | `""` | Workspace ID for diagnostics. Empty disables. |

#### Outputs

| Output | Description |
|---|---|
| `id` | ARM resource ID |
| `name` | VNet name |
| `address_space` | List of address spaces |
| `resource_group_name` | Resource group name |

#### Usage Examples

**Minimal:**

```hcl
module "vnet" {
  source              = "../modules/virtual-network"
  name                = "platform-dev-eus2-vnet"
  resource_group_name = module.resource_group.name
  location            = var.location
  address_space       = ["10.0.0.0/16"]
}
```

**Production-grade (with diagnostics and custom DNS):**

```hcl
module "vnet" {
  source              = "../modules/virtual-network"
  name                = module.naming.virtual_network
  resource_group_name = module.resource_group.name
  location            = var.location
  address_space       = ["10.0.0.0/16"]
  dns_servers         = ["10.0.0.4", "10.0.0.5"]  # custom DNS forwarders
  log_analytics_workspace_id = module.log_analytics.id
  tags                = local.common_tags
}
```

#### Dependencies

- `resource-group`
- `log-analytics` (optional, for diagnostics)

#### Gotchas

- Plan address space carefully. VNet address spaces cannot overlap if you plan to use VNet peering. Reserve separate, non-overlapping CIDR ranges for dev, staging, and prod.
- `dns_servers` overrides Azure's built-in DNS. If you set custom DNS servers, ensure those servers can resolve `*.privatelink.*` zones and Azure-internal FQDNs, or hybrid name resolution will break.
- Diagnostic settings are created as a child resource of the VNet. If you later remove `log_analytics_workspace_id`, the diagnostic setting resource will be destroyed on the next apply.

---

### subnet

**Path**: `modules/subnet`

#### Purpose

Creates a subnet inside a VNet and optionally associates an NSG with it in the same resource. Supports service endpoint configuration and subnet delegation for managed services (e.g., Azure Container Instances, API Management).

This is the foundational network placement module. AKS node pools, private endpoints, and application subnets all use this module, each with different CIDR ranges and configurations.

#### Inputs

| Variable | Type | Required | Default | Description |
|---|---|---|---|---|
| `name` | `string` | Yes | — | Subnet name. |
| `resource_group_name` | `string` | Yes | — | Resource group of the parent VNet. |
| `virtual_network_name` | `string` | Yes | — | Name of the parent VNet. |
| `address_prefixes` | `list(string)` | Yes | — | CIDR range(s) for the subnet. |
| `delegation` | `object` | No | `null` | Service delegation block (`name`, `service_delegation.name`, `service_delegation.actions`). |
| `service_endpoints` | `list(string)` | No | `[]` | Service endpoints (e.g., `["Microsoft.KeyVault", "Microsoft.Storage"]`). |
| `network_security_group_id` | `string` | No | `""` | NSG ARM ID to associate. Empty skips association. |
| `private_endpoint_network_policies` | `string` | No | `"Enabled"` | Set to `"Disabled"` for subnets that host private endpoints. |

#### Outputs

| Output | Description |
|---|---|
| `id` | Subnet ARM resource ID |
| `name` | Subnet name |
| `address_prefixes` | Subnet CIDR range(s) |
| `resource_group_name` | Resource group name |
| `virtual_network_name` | Parent VNet name |

#### Usage Examples

**Minimal (AKS subnet):**

```hcl
module "subnet_aks" {
  source               = "../modules/subnet"
  name                 = "snet-aks"
  resource_group_name  = module.resource_group.name
  virtual_network_name = module.vnet.name
  address_prefixes     = ["10.0.0.0/22"]
}
```

**Production-grade (private endpoint subnet with NSG):**

```hcl
module "subnet_private_endpoints" {
  source               = "../modules/subnet"
  name                 = "snet-pe"
  resource_group_name  = module.resource_group.name
  virtual_network_name = module.vnet.name
  address_prefixes     = ["10.0.5.0/24"]

  # Required for subnets that host private endpoints
  private_endpoint_network_policies = "Disabled"

  network_security_group_id = module.nsg_pe.id
}
```

**Subnet with service endpoints (for Key Vault / Storage firewall rules):**

```hcl
module "subnet_services" {
  source               = "../modules/subnet"
  name                 = "snet-services"
  resource_group_name  = module.resource_group.name
  virtual_network_name = module.vnet.name
  address_prefixes     = ["10.0.4.0/24"]

  service_endpoints = [
    "Microsoft.KeyVault",
    "Microsoft.Storage",
  ]

  network_security_group_id = module.nsg_services.id
}
```

#### Dependencies

- `resource-group`
- `virtual-network` (provides `virtual_network_name`)
- `network-security-group` (optional, provides `network_security_group_id`)

#### Gotchas

- **Private endpoint subnets require `private_endpoint_network_policies = "Disabled"`**. Without this, private endpoint DNS resolution and routing will not work correctly. This is the single most common misconfiguration.
- Service endpoints and private endpoints solve different problems: service endpoints extend the VNet identity to Azure PaaS services over the public backbone; private endpoints bring the service into your VNet with a private IP. For production workloads, prefer private endpoints.
- NSG association is handled inside this module (`azurerm_subnet_network_security_group_association`). Do not also create a separate association resource in your root module, as this will conflict.
- The `delegation` block locks the subnet to a specific service. Once delegated, only that service can deploy into the subnet. AKS node pools do not require delegation unless using the `azure` CNI with subnet-per-node-pool mode.

---

### network-security-group

**Path**: `modules/network-security-group`

#### Purpose

Creates an Azure Network Security Group (NSG) with configurable inbound/outbound security rules. If no rules are provided, the module automatically applies a default `DenyAllInbound` rule at priority 4096, ensuring that subnets are never left open by accident.

Associate the NSG with subnets by passing `module.nsg.id` to the `subnet` module's `network_security_group_id` variable.

#### Inputs

| Variable | Type | Required | Default | Description |
|---|---|---|---|---|
| `name` | `string` | Yes | — | NSG name. |
| `resource_group_name` | `string` | Yes | — | Resource group to deploy into. |
| `location` | `string` | Yes | — | Azure region. |
| `security_rules` | `list(object)` | No | `[]` | List of security rules. See schema below. When empty, `DenyAllInbound` is applied. |
| `tags` | `map(string)` | No | `{}` | Tags to apply. |
| `log_analytics_workspace_id` | `string` | No | `""` | Workspace ID for NSG flow log diagnostics. |

**Security rule object schema:**

```hcl
{
  name                       = string  # Rule name
  priority                   = number  # 100–4096
  direction                  = string  # "Inbound" or "Outbound"
  access                     = string  # "Allow" or "Deny"
  protocol                   = string  # "Tcp", "Udp", "Icmp", "*"
  source_port_range          = string  # e.g., "*" or "443"
  destination_port_range     = string  # e.g., "443" or "8080-8090"
  source_address_prefix      = string  # e.g., "10.0.0.0/16" or "VirtualNetwork"
  destination_address_prefix = string  # e.g., "*" or "AzureLoadBalancer"
}
```

#### Outputs

| Output | Description |
|---|---|
| `id` | NSG ARM resource ID |
| `name` | NSG name |
| `resource_group_name` | Resource group name |

#### Usage Examples

**Minimal (default deny-all — suitable for private endpoint subnets):**

```hcl
module "nsg_pe" {
  source              = "../modules/network-security-group"
  name                = "platform-dev-eus2-nsg-pe"
  resource_group_name = module.resource_group.name
  location            = var.location
}
```

**Production-grade (AKS subnet NSG with explicit rules):**

```hcl
module "nsg_aks" {
  source              = "../modules/network-security-group"
  name                = module.naming.network_security_group
  resource_group_name = module.resource_group.name
  location            = var.location

  security_rules = [
    {
      name                       = "AllowApiServerInbound"
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "443"
      source_address_prefix      = "AzureCloud"
      destination_address_prefix = "*"
    },
    {
      name                       = "AllowAzureLoadBalancer"
      priority                   = 200
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "AzureLoadBalancer"
      destination_address_prefix = "*"
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
    },
  ]

  log_analytics_workspace_id = module.log_analytics.id
  tags                       = local.common_tags
}
```

#### Dependencies

- `resource-group`
- `log-analytics` (optional, for diagnostics)

#### Gotchas

- When `security_rules = []`, the module inserts `DenyAllInbound` at priority 4096. If you then add your own rules later, the default rule stays and does not conflict as long as your rules have lower priority numbers. If you want different default behavior, explicitly provide your own deny rule.
- Diagnostic settings created by this module capture `NetworkSecurityGroupEvent` and `NetworkSecurityGroupRuleCounter` logs. This is useful for auditing but can generate significant volume in high-traffic environments. Set `daily_quota_gb` on your workspace accordingly.
- NSG rules apply at the subnet level. Do not confuse with Application Security Groups (ASGs), which are not currently supported by this module.

---

### private-endpoint

**Path**: `modules/private-endpoint`

#### Purpose

Creates an Azure Private Endpoint, which places a private IP address for a PaaS service (Key Vault, Storage Account, etc.) directly inside your VNet. This allows resources in the VNet to reach those services without traversing the public internet.

Optionally associates a Private DNS Zone Group with the endpoint, which configures automatic DNS resolution for the private IP.

#### Inputs

| Variable | Type | Required | Default | Description |
|---|---|---|---|---|
| `name` | `string` | Yes | — | Private endpoint name. |
| `resource_group_name` | `string` | Yes | — | Resource group to deploy into. |
| `location` | `string` | Yes | — | Azure region. |
| `subnet_id` | `string` | Yes | — | ID of the subnet to place the endpoint in. |
| `private_connection_resource_id` | `string` | Yes | — | ARM ID of the target resource (Key Vault, Storage Account, etc.). |
| `subresource_names` | `list(string)` | Yes | — | Subresource type(s). E.g., `["vault"]` for Key Vault, `["blob"]` for Storage blob. |
| `is_manual_connection` | `bool` | No | `false` | Whether connection requires manual approval. |
| `private_dns_zone_ids` | `list(string)` | No | `[]` | Private DNS zone ARM IDs to associate. |
| `tags` | `map(string)` | No | `{}` | Tags to apply. |

**Common subresource names by service:**

| Service | Subresource |
|---|---|
| Key Vault | `vault` |
| Storage blob | `blob` |
| Storage file | `file` |
| Storage queue | `queue` |
| Storage table | `table` |
| Azure SQL | `sqlServer` |
| Cosmos DB | `Sql` |

#### Outputs

| Output | Description |
|---|---|
| `id` | Private endpoint ARM resource ID |
| `name` | Private endpoint name |
| `private_ip_address` | Private IP assigned to the endpoint |
| `network_interface_id` | NIC ARM resource ID |
| `custom_dns_configs` | Custom DNS configuration entries |

#### Usage Examples

**Minimal (Key Vault private endpoint):**

```hcl
module "pe_key_vault" {
  source              = "../modules/private-endpoint"
  name                = "platform-dev-eus2-pe-kv"
  resource_group_name = module.resource_group.name
  location            = var.location
  subnet_id           = module.subnet_private_endpoints.id

  private_connection_resource_id = module.key_vault.id
  subresource_names              = ["vault"]
}
```

**Production-grade (with Private DNS Zone integration):**

```hcl
resource "azurerm_private_dns_zone" "key_vault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = module.resource_group.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "key_vault" {
  name                  = "kv-dns-link"
  resource_group_name   = module.resource_group.name
  private_dns_zone_name = azurerm_private_dns_zone.key_vault.name
  virtual_network_id    = module.vnet.id
}

module "pe_key_vault" {
  source              = "../modules/private-endpoint"
  name                = module.naming.private_endpoint
  resource_group_name = module.resource_group.name
  location            = var.location
  subnet_id           = module.subnet_private_endpoints.id

  private_connection_resource_id = module.key_vault.id
  subresource_names              = ["vault"]
  private_dns_zone_ids           = [azurerm_private_dns_zone.key_vault.id]
  tags                           = local.common_tags
}
```

#### Dependencies

- `resource-group`
- `subnet` (provides `subnet_id`; must have `private_endpoint_network_policies = "Disabled"`)
- The target resource (e.g., `key-vault`, `storage-account`) for its ARM ID

#### Gotchas

- **The subnet must have `private_endpoint_network_policies = "Disabled"`**. This is the most common reason private endpoints fail to connect.
- Without a Private DNS Zone Group, resources in the VNet can reach the private IP directly, but DNS will still resolve to the public FQDN. Always pair private endpoints with private DNS zones in production to get transparent DNS resolution.
- Private DNS zones must be linked to the VNet via `azurerm_private_dns_zone_virtual_network_link`. This linkage is not created by the private-endpoint module; you must create it separately (see example above).
- The `custom_dns_configs` output is useful for populating DNS records in an external DNS system when not using Azure Private DNS.

---

### key-vault

**Path**: `modules/key-vault`

#### Purpose

Creates an Azure Key Vault with secure defaults: RBAC authorization enabled, purge protection on, public network access off, and a `Deny` default network ACL action. Use this module for storing secrets, certificates, and encryption keys.

Optionally creates a diagnostic setting to capture audit logs (including all secret access events) to Log Analytics.

#### Inputs

| Variable | Type | Required | Default | Description |
|---|---|---|---|---|
| `name` | `string` | Yes | — | Key Vault name. Max 24 chars, alphanumeric and hyphens. Validated. |
| `resource_group_name` | `string` | Yes | — | Resource group to deploy into. |
| `location` | `string` | Yes | — | Azure region. |
| `tenant_id` | `string` | Yes | — | Azure AD tenant ID. |
| `sku_name` | `string` | No | `"standard"` | `standard` or `premium` (premium required for HSM-backed keys). |
| `enable_rbac_authorization` | `bool` | No | `true` | Use RBAC rather than access policies (strongly recommended). |
| `purge_protection_enabled` | `bool` | No | `true` | Prevents permanent deletion during soft-delete retention window. |
| `soft_delete_retention_days` | `number` | No | `90` | Days to retain soft-deleted objects. 7–90. |
| `public_network_access_enabled` | `bool` | No | `false` | Whether public access is allowed. |
| `network_acls_default_action` | `string` | No | `"Deny"` | `Allow` or `Deny`. |
| `network_acls_ip_rules` | `list(string)` | No | `[]` | Allowed public IPs/CIDRs. |
| `network_acls_virtual_network_subnet_ids` | `list(string)` | No | `[]` | Allowed subnet IDs (requires service endpoint on subnet). |
| `tags` | `map(string)` | No | `{}` | Tags to apply. |
| `log_analytics_workspace_id` | `string` | No | `""` | Workspace ID for audit log diagnostics. |

#### Outputs

| Output | Description |
|---|---|
| `id` | Key Vault ARM resource ID |
| `name` | Key Vault name |
| `vault_uri` | HTTPS URI for SDK access (e.g., `https://platform-prod-eus2-kv.vault.azure.net/`) |
| `tenant_id` | Azure AD tenant ID |
| `resource_group_name` | Resource group name |

#### Usage Examples

**Minimal:**

```hcl
module "key_vault" {
  source              = "../modules/key-vault"
  name                = "myapp-dev-eus2-kv"
  resource_group_name = module.resource_group.name
  location            = var.location
  tenant_id           = data.azurerm_client_config.current.tenant_id
}
```

**Production-grade (private access, diagnostics, subnet allowlist):**

```hcl
module "key_vault" {
  source              = "../modules/key-vault"
  name                = module.naming.key_vault
  resource_group_name = module.resource_group.name
  location            = var.location
  tenant_id           = data.azurerm_client_config.current.tenant_id

  sku_name                      = "premium"
  purge_protection_enabled      = true
  soft_delete_retention_days    = 90
  public_network_access_enabled = false

  network_acls_default_action              = "Deny"
  network_acls_virtual_network_subnet_ids  = [module.subnet_services.id]

  log_analytics_workspace_id = module.log_analytics.id
  tags                       = local.common_tags
}
```

#### Dependencies

- `resource-group`
- `log-analytics` (optional, for diagnostics)

#### Common Patterns

**Granting access via RBAC after creation:**

```hcl
module "kv_rbac" {
  source = "../modules/rbac-assignment"

  role_assignments = {
    aks_kv_secrets_user = {
      scope                = module.key_vault.id
      role_definition_name = "Key Vault Secrets User"
      principal_id         = module.aks_identity.principal_id
      description          = "AKS workload identity reads secrets"
    }
  }
}
```

#### Gotchas

- **Purge protection cannot be disabled once enabled.** If you enable it and later want to delete and recreate a vault with the same name, you must wait out the soft-delete retention period (up to 90 days) or choose a new name.
- With `public_network_access_enabled = false` and `network_acls_default_action = "Deny"` (both defaults), the Key Vault is only accessible via private endpoint or from subnets listed in `network_acls_virtual_network_subnet_ids`. Your Terraform runner must also have network access. Add a CI/CD runner IP to `network_acls_ip_rules` or run Terraform from inside the VNet.
- The `AzureServices` bypass is hardcoded in the module (`bypass = "AzureServices"`), allowing trusted Azure services (Azure Backup, Disk Encryption, etc.) to access the vault even when public access is disabled.
- RBAC authorization and access policies are mutually exclusive. This module defaults to RBAC (`enable_rbac_authorization = true`). Do not attempt to create legacy access policies on RBAC-enabled vaults.

---

### storage-account

**Path**: `modules/storage-account`

#### Purpose

Creates an Azure Storage Account with secure defaults (no public access, no shared key auth, HTTPS only, TLS 1.2 minimum, soft delete enabled, versioning on). Supports blob container creation, lifecycle management rules, customer-managed key (CMK) encryption, and Log Analytics diagnostics.

#### Inputs

| Variable | Type | Required | Default | Description |
|---|---|---|---|---|
| `name` | `string` | Yes | — | Storage account name. 3–24 chars, lowercase alphanumeric only (no hyphens). Validated. |
| `resource_group_name` | `string` | Yes | — | Resource group to deploy into. |
| `location` | `string` | Yes | — | Azure region. |
| `account_tier` | `string` | No | `"Standard"` | `Standard` or `Premium`. |
| `account_replication_type` | `string` | No | `"LRS"` | `LRS`, `GRS`, `RAGRS`, `ZRS`, `GZRS`, `RAGZRS`. |
| `account_kind` | `string` | No | `"StorageV2"` | Storage account kind. |
| `min_tls_version` | `string` | No | `"TLS1_2"` | Minimum TLS version. |
| `https_traffic_only_enabled` | `bool` | No | `true` | Enforce HTTPS. |
| `public_network_access_enabled` | `bool` | No | `false` | Allow public access. |
| `shared_access_key_enabled` | `bool` | No | `false` | Enable SAS key auth (prefer RBAC). |
| `blob_soft_delete_retention_days` | `number` | No | `30` | Blob soft-delete retention (1–365). |
| `container_soft_delete_retention_days` | `number` | No | `30` | Container soft-delete retention (1–365). |
| `versioning_enabled` | `bool` | No | `true` | Enable blob versioning. |
| `network_rules_default_action` | `string` | No | `"Deny"` | `Allow` or `Deny`. |
| `network_rules_ip_rules` | `list(string)` | No | `[]` | Allowed public IPs. |
| `network_rules_virtual_network_subnet_ids` | `list(string)` | No | `[]` | Allowed subnet IDs. |
| `network_rules_bypass` | `list(string)` | No | `["AzureServices"]` | Services to bypass rules. |
| `containers` | `map(object)` | No | `{}` | Map of container name to `{ access_type = "private" }`. |
| `lifecycle_rules` | `list(object)` | No | `[]` | Blob lifecycle management rules. |
| `cmk_key_vault_key_id` | `string` | No | `""` | Key Vault Key ID for CMK encryption. Empty uses Microsoft-managed keys. |
| `cmk_user_assigned_identity_id` | `string` | No | `""` | Identity ID for CMK key access. Required when `cmk_key_vault_key_id` is set. |
| `log_analytics_workspace_id` | `string` | No | `""` | Workspace ID for diagnostics. |
| `tags` | `map(string)` | No | `{}` | Tags to apply. |

**Lifecycle rule object schema:**

```hcl
{
  name                       = string         # Rule name
  enabled                    = optional(bool, true)
  prefix_match               = optional(list(string), [])
  tier_to_cool_after_days    = optional(number, null)
  tier_to_archive_after_days = optional(number, null)
  delete_after_days          = optional(number, null)
}
```

#### Outputs

| Output | Description |
|---|---|
| `id` | Storage account ARM resource ID |
| `name` | Storage account name |
| `primary_blob_endpoint` | Primary blob service endpoint URL |
| `primary_connection_string` | Connection string (sensitive) |
| `resource_group_name` | Resource group name |

#### Usage Examples

**Minimal:**

```hcl
module "storage_account" {
  source              = "../modules/storage-account"
  name                = "platformdeveus2st"
  resource_group_name = module.resource_group.name
  location            = var.location
}
```

**Production-grade (ZRS replication, CMK, containers, lifecycle):**

```hcl
module "storage_account" {
  source              = "../modules/storage-account"
  name                = module.naming.storage_account
  resource_group_name = module.resource_group.name
  location            = var.location

  account_tier             = "Standard"
  account_replication_type = "ZRS"

  public_network_access_enabled = false
  shared_access_key_enabled     = false

  # CMK encryption
  cmk_key_vault_key_id          = azurerm_key_vault_key.storage_cmk.id
  cmk_user_assigned_identity_id = module.storage_identity.id

  containers = {
    tfstate = { access_type = "private" }
    data    = { access_type = "private" }
    logs    = { access_type = "private" }
  }

  lifecycle_rules = [
    {
      name                       = "archive-old-blobs"
      tier_to_cool_after_days    = 30
      tier_to_archive_after_days = 90
      delete_after_days          = 365
    }
  ]

  log_analytics_workspace_id = module.log_analytics.id
  tags                       = local.common_tags
}
```

#### Dependencies

- `resource-group`
- `managed-identity` (if using CMK)
- `key-vault` + a key resource (if using CMK)
- `log-analytics` (optional, for diagnostics)

#### Gotchas

- Storage account names are globally unique across Azure. Always use `module.naming.storage_account` with a `unique_seed` (subscription ID) to avoid name collisions.
- With `shared_access_key_enabled = false`, SAS tokens and connection strings do not work. All access must go through Azure AD (RBAC). Ensure your application and CI/CD tooling supports Azure AD authentication before disabling shared keys.
- CMK requires granting the storage identity `Key Vault Crypto Service Encryption User` on the Key Vault before the storage account is created. Use `depends_on` or ensure the RBAC assignment is applied first.
- The `primary_connection_string` output is sensitive. It appears in state. If you're using RBAC-only access, do not use this output — it is only useful for legacy applications that require a connection string.

---

### aks-cluster

**Path**: `modules/aks-cluster`

#### Purpose

Creates a production-ready Azure Kubernetes Service (AKS) cluster with:

- User-assigned managed identity for the control plane
- Azure CNI with overlay networking (default)
- OIDC issuer and workload identity enabled
- Azure Policy add-on enabled
- Kubernetes RBAC with Azure AD integration
- Auto-scaling on all node pools
- OMS agent integration with Log Analytics
- Configurable maintenance windows
- Support for multiple additional node pools

#### Inputs

| Variable | Type | Required | Default | Description |
|---|---|---|---|---|
| `name` | `string` | Yes | — | AKS cluster name. |
| `resource_group_name` | `string` | Yes | — | Resource group to deploy into. |
| `location` | `string` | Yes | — | Azure region. |
| `dns_prefix` | `string` | Yes | — | DNS prefix for the cluster API server FQDN. |
| `kubernetes_version` | `string` | No | `null` | Kubernetes version. `null` uses latest stable. |
| `sku_tier` | `string` | No | `"Standard"` | `Free`, `Standard`, or `Premium`. Use `Standard` or `Premium` for production (99.95% SLA). |
| `identity_type` | `string` | No | `"UserAssigned"` | `SystemAssigned` or `UserAssigned`. |
| `user_assigned_identity_id` | `string` | No | `""` | Required when `identity_type = "UserAssigned"`. |
| `default_node_pool` | `object` | No | `{}` | System node pool config (see schema). |
| `additional_node_pools` | `map(object)` | No | `{}` | Map of user node pools. |
| `network_plugin` | `string` | No | `"azure"` | `azure` or `kubenet`. |
| `network_plugin_mode` | `string` | No | `"overlay"` | `overlay` or `""`. |
| `network_policy` | `string` | No | `"azure"` | `azure`, `calico`, or `cilium`. |
| `service_cidr` | `string` | No | `"172.16.0.0/16"` | Kubernetes service CIDR. Must not overlap VNet. |
| `dns_service_ip` | `string` | No | `"172.16.0.10"` | Kubernetes DNS service IP (must be within `service_cidr`). |
| `oidc_issuer_enabled` | `bool` | No | `true` | Enable OIDC issuer. |
| `workload_identity_enabled` | `bool` | No | `true` | Enable workload identity. |
| `azure_policy_enabled` | `bool` | No | `true` | Enable Azure Policy add-on. |
| `role_based_access_control_enabled` | `bool` | No | `true` | Enable Kubernetes RBAC. |
| `azure_active_directory_role_based_access_control` | `object` | No | `{}` | Azure AD RBAC config (admin group IDs, azure_rbac_enabled). |
| `maintenance_window` | `object` | No | Sunday 00:00–04:00 | Maintenance window schedule. |
| `log_analytics_workspace_id` | `string` | No | `""` | Workspace ID for OMS agent and diagnostics. |
| `tags` | `map(string)` | No | `{}` | Tags to apply. |

**Default node pool object schema:**

```hcl
{
  name                         = optional(string, "system")
  vm_size                      = optional(string, "Standard_B2s")
  min_count                    = optional(number, 1)
  max_count                    = optional(number, 3)
  os_disk_size_gb              = optional(number, 30)
  os_sku                       = optional(string, "AzureLinux")
  zones                        = optional(list(string), ["1", "2", "3"])
  max_pods                     = optional(number, 30)
  only_critical_addons_enabled = optional(bool, true)
  vnet_subnet_id               = optional(string, null)
}
```

**Additional node pool object schema:**

```hcl
{
  vm_size         = optional(string, "Standard_B2s")
  min_count       = optional(number, 1)
  max_count       = optional(number, 3)
  os_disk_size_gb = optional(number, 30)
  os_sku          = optional(string, "AzureLinux")
  zones           = optional(list(string), ["1", "2", "3"])
  max_pods        = optional(number, 30)
  mode            = optional(string, "User")
  node_labels     = optional(map(string), {})
  node_taints     = optional(list(string), [])
  vnet_subnet_id  = optional(string, null)
}
```

#### Outputs

| Output | Description |
|---|---|
| `id` | AKS cluster ARM resource ID |
| `name` | Cluster name |
| `fqdn` | API server FQDN |
| `kube_config_raw` | Raw kubeconfig (sensitive) |
| `oidc_issuer_url` | OIDC issuer URL (for workload identity federation) |
| `kubelet_identity` | Kubelet managed identity object |
| `node_resource_group` | Auto-generated node resource group name |
| `host` | Kubernetes API server host (sensitive) |

#### Usage Examples

**Minimal:**

```hcl
module "aks_cluster" {
  source              = "../modules/aks-cluster"
  name                = "platform-dev-eus2-aks"
  resource_group_name = module.resource_group.name
  location            = var.location
  dns_prefix          = "platform-dev"

  user_assigned_identity_id = module.aks_identity.id
}
```

**Production-grade (multi-zone, user node pool, AD integration, monitoring):**

```hcl
module "aks_cluster" {
  source              = "../modules/aks-cluster"
  name                = module.naming.aks_cluster
  resource_group_name = module.resource_group.name
  location            = var.location
  dns_prefix          = "${var.project}-${var.environment}"
  kubernetes_version  = "1.30"
  sku_tier            = "Standard"

  identity_type             = "UserAssigned"
  user_assigned_identity_id = module.aks_identity.id

  default_node_pool = {
    name                         = "system"
    vm_size                      = "Standard_D2s_v3"
    min_count                    = 2
    max_count                    = 5
    os_disk_size_gb              = 50
    os_sku                       = "AzureLinux"
    zones                        = ["1", "2", "3"]
    only_critical_addons_enabled = true
    vnet_subnet_id               = module.subnet_aks.id
  }

  additional_node_pools = {
    workload = {
      vm_size        = "Standard_D4s_v3"
      min_count      = 2
      max_count      = 20
      os_disk_size_gb = 50
      zones          = ["1", "2", "3"]
      mode           = "User"
      node_labels    = { "workload" = "application" }
      vnet_subnet_id = module.subnet_aks.id
    }
  }

  network_plugin      = "azure"
  network_plugin_mode = "overlay"
  network_policy      = "azure"
  service_cidr        = "172.16.0.0/16"
  dns_service_ip      = "172.16.0.10"

  oidc_issuer_enabled       = true
  workload_identity_enabled = true
  azure_policy_enabled      = true

  azure_active_directory_role_based_access_control = {
    admin_group_object_ids = [var.aks_admin_group_id]
    azure_rbac_enabled     = true
  }

  maintenance_window = {
    allowed = [
      { day = "Saturday", hours = [0, 1, 2, 3, 4] },
      { day = "Sunday",   hours = [0, 1, 2, 3, 4] },
    ]
  }

  log_analytics_workspace_id = module.log_analytics.id
  tags                       = local.common_tags
}
```

#### Dependencies

- `resource-group`
- `managed-identity` (for `user_assigned_identity_id`)
- `subnet` (for node pool `vnet_subnet_id`)
- `log-analytics` (optional, for OMS agent and diagnostics)

#### Gotchas

- **`only_critical_addons_enabled = true` on the system pool** is the correct pattern. It taints the system pool with `CriticalAddonsOnly`, forcing user workloads onto dedicated user node pools. Always add at least one user node pool for application workloads.
- `service_cidr` must not overlap with any VNet address space or any other subnet range. The default `172.16.0.0/16` works in most cases. Document this range to avoid future overlap.
- `workload_identity_enabled` requires `oidc_issuer_enabled = true`. Both are `true` by default. Do not disable `oidc_issuer_enabled` if workload identity is needed.
- The `kube_config_raw` and `host` outputs are sensitive. They are stored in state. Use a secrets manager or CI/CD variable store to handle kubeconfigs; do not output them in plaintext.
- AKS upgrades can temporarily exceed `max_count` during node surge. Ensure your VNet subnet has enough IP space for surge capacity. With `max_count = 20` and a `/24` subnet (254 IPs), you have enough headroom, but with `max_pods = 30` per node, a `/22` is safer.
- The `node_resource_group` is auto-generated by Azure. Do not manually place resources in it.

---

### rbac-assignment

**Path**: `modules/rbac-assignment`

#### Purpose

Creates Azure role assignments and optionally custom role definitions. This module is the central place for all RBAC in the project. Instead of spreading `azurerm_role_assignment` resources across multiple modules, define all grants here with clear descriptions.

A built-in precondition guards against accidentally granting the `Owner` role: any `Owner` assignment requires the string `EXCEPTION-APPROVED` in the `description` field, providing an audit trail.

#### Inputs

| Variable | Type | Required | Default | Description |
|---|---|---|---|---|
| `role_assignments` | `map(object)` | Yes | — | Map of role assignments. Key is a friendly name. |
| `custom_role_definitions` | `map(object)` | No | `{}` | Map of custom role definitions to create. |

**Role assignment object schema:**

```hcl
{
  scope                = string                              # ARM scope (subscription, resource group, or resource ID)
  role_definition_name = string                              # Built-in or custom role name
  principal_id         = string                              # Service principal / group / user object ID
  principal_type       = optional(string, "ServicePrincipal") # "ServicePrincipal", "Group", "User"
  description          = optional(string, "")               # Human-readable description of why this assignment exists
}
```

**Custom role definition object schema:**

```hcl
{
  name        = string
  scope       = string
  description = optional(string, "")
  permissions = object({
    actions          = list(string)
    not_actions      = optional(list(string), [])
    data_actions     = optional(list(string), [])
    not_data_actions = optional(list(string), [])
  })
  assignable_scopes = list(string)
}
```

#### Outputs

| Output | Description |
|---|---|
| `role_assignment_ids` | Map of assignment key to ARM resource ID |
| `custom_role_definition_ids` | Map of role name to role definition resource ID |

#### Usage Examples

**Minimal (single role assignment):**

```hcl
module "rbac" {
  source = "../modules/rbac-assignment"

  role_assignments = {
    aks_acr_pull = {
      scope                = azurerm_container_registry.this.id
      role_definition_name = "AcrPull"
      principal_id         = module.aks_cluster.kubelet_identity[0].object_id
      description          = "AKS kubelet pulls images from ACR"
    }
  }
}
```

**Production-grade (multiple assignments, custom role):**

```hcl
module "rbac" {
  source = "../modules/rbac-assignment"

  role_assignments = {
    aks_kv_secrets = {
      scope                = module.key_vault.id
      role_definition_name = "Key Vault Secrets User"
      principal_id         = module.aks_identity.principal_id
      description          = "AKS reads secrets from Key Vault"
    }
    storage_blob_contributor = {
      scope                = module.storage_account.id
      role_definition_name = "Storage Blob Data Contributor"
      principal_id         = module.aks_identity.principal_id
      description          = "AKS workloads write to storage"
    }
    dev_team_contributor = {
      scope                = "/subscriptions/${var.subscription_id}/resourceGroups/${module.resource_group.name}"
      role_definition_name = "Contributor"
      principal_id         = var.dev_team_group_id
      principal_type       = "Group"
      description          = "Dev team deploys to dev resource group"
    }
  }

  custom_role_definitions = {
    restricted_contributor = {
      name        = "Restricted Contributor"
      scope       = "/subscriptions/${var.subscription_id}"
      description = "Contributor without ability to modify RBAC or delete resource groups"
      permissions = {
        actions = ["*"]
        not_actions = [
          "Microsoft.Authorization/roleAssignments/write",
          "Microsoft.Authorization/roleAssignments/delete",
          "Microsoft.Resources/subscriptions/resourceGroups/delete",
        ]
      }
      assignable_scopes = ["/subscriptions/${var.subscription_id}"]
    }
  }
}
```

#### Dependencies

- No Azure resource dependencies (role assignments reference existing resource IDs).
- Logically depends on `managed-identity`, `aks-cluster`, `key-vault`, `storage-account`, or any resource whose ARM ID is used as a scope or whose principal ID is assigned.

#### Gotchas

- Role assignment creation can fail with `PrincipalNotFound` if a newly created managed identity has not yet propagated through Azure AD. Add a `time_sleep` resource or `depends_on` referencing the identity if this occurs.
- The `Owner` precondition check runs during `terraform plan`. If you attempt an Owner assignment without `EXCEPTION-APPROVED` in the description, the plan will fail with a clear error message.
- Custom role definitions are subscription-scoped. Creating the same custom role in multiple subscriptions requires separate module invocations with different `scope` values.
- Scope strings must be full ARM IDs. For subscription scope: `/subscriptions/{subscription_id}`. For resource group scope: `/subscriptions/{subscription_id}/resourceGroups/{rg_name}`.

---

### azure-policy

**Path**: `modules/azure-policy`

#### Purpose

Creates custom Azure Policy definitions and assigns them at the subscription scope. Use this module to enforce organizational governance standards: required tags, banned configurations, HTTPS enforcement, etc.

Both `policy_definitions` and `policy_assignments` are maps, so you can define and assign multiple policies in a single module call. Policy rules are provided as JSON-encoded strings (use `jsonencode()` for type safety).

#### Inputs

| Variable | Type | Required | Default | Description |
|---|---|---|---|---|
| `scope` | `string` | Yes | — | Default scope for policy definitions (subscription ID or management group ID). |
| `policy_definitions` | `map(object)` | No | `{}` | Custom policy definitions to create. |
| `policy_assignments` | `map(object)` | No | `{}` | Policy assignments to create. |
| `use_builtin_policies` | `bool` | No | `true` | Reserved for future built-in policy assignment support. |

**Policy definition object schema:**

```hcl
{
  display_name = string
  description  = optional(string, "")
  mode         = optional(string, "All")    # "All" or "Indexed"
  policy_rule  = string                     # JSON-encoded policy rule
  metadata     = optional(string, "")       # JSON-encoded metadata
  parameters   = optional(string, "")       # JSON-encoded parameters schema
}
```

**Policy assignment object schema:**

```hcl
{
  policy_definition_id = string             # ARM ID of the policy definition
  display_name         = string
  description          = optional(string, "")
  scope                = string             # Subscription ID for assignment
  parameters           = optional(string, "") # JSON-encoded parameter values
  enforce              = optional(bool, true) # false = "audit" mode
  identity_type        = optional(string, "") # "SystemAssigned" for remediation tasks
  location             = optional(string, "") # Required when identity_type is set
}
```

#### Outputs

| Output | Description |
|---|---|
| `policy_definition_ids` | Map of definition key to ARM policy definition ID |
| `policy_assignment_ids` | Map of assignment key to ARM assignment ID |

#### Usage Examples

**Minimal (single policy):**

```hcl
data "azurerm_subscription" "current" {}

module "policy" {
  source = "../modules/azure-policy"
  scope  = data.azurerm_subscription.current.id

  policy_definitions = {
    require-env-tag = {
      display_name = "Require environment tag"
      policy_rule  = jsonencode({
        if   = { field = "tags['environment']", exists = "false" }
        then = { effect = "deny" }
      })
    }
  }

  policy_assignments = {
    enforce-env-tag = {
      policy_definition_id = module.policy.policy_definition_ids["require-env-tag"]
      display_name         = "Enforce environment tag"
      scope                = data.azurerm_subscription.current.id
      enforce              = true
    }
  }
}
```

**Production-grade (multiple governance policies):**

```hcl
module "governance_policy" {
  source = "../modules/azure-policy"
  scope  = data.azurerm_subscription.current.id

  policy_definitions = {
    deny-public-storage = {
      display_name = "Deny public blob access on storage accounts"
      mode         = "All"
      policy_rule  = jsonencode({
        if = { allOf = [
          { field = "type", equals = "Microsoft.Storage/storageAccounts" },
          { field = "Microsoft.Storage/storageAccounts/allowBlobPublicAccess", notEquals = "false" }
        ]}
        then = { effect = "deny" }
      })
    }
    require-tls12 = {
      display_name = "Require TLS 1.2 on storage accounts"
      mode         = "Indexed"
      policy_rule  = jsonencode({
        if = { allOf = [
          { field = "type", equals = "Microsoft.Storage/storageAccounts" },
          { field = "Microsoft.Storage/storageAccounts/minimumTlsVersion", notEquals = "TLS1_2" }
        ]}
        then = { effect = "audit" }
      })
    }
  }

  policy_assignments = {
    deny-public-storage = {
      policy_definition_id = module.governance_policy.policy_definition_ids["deny-public-storage"]
      display_name         = "Deny public storage accounts"
      scope                = data.azurerm_subscription.current.id
      enforce              = true
    }
    audit-tls12 = {
      policy_definition_id = module.governance_policy.policy_definition_ids["require-tls12"]
      display_name         = "Audit storage TLS version"
      scope                = data.azurerm_subscription.current.id
      enforce              = false  # audit only, not deny
    }
  }
}
```

#### Dependencies

- No module dependencies.
- Requires a `data "azurerm_subscription" "current" {}` data source for the subscription scope.

#### Gotchas

- Policy assignments reference `policy_definition_id` (the ARM resource ID), not the definition key. Use `module.azure_policy.policy_definition_ids["key"]` to get the ID of a policy you just defined in the same module call.
- `enforce = false` puts the policy in audit mode: resources are flagged as non-compliant but not blocked. Use this when rolling out new policies to assess impact before enforcing.
- Assigning a `deny` policy to a subscription where existing resources already violate it will not remove the existing resources. It only prevents new violating resources. Use `effect = "audit"` first to identify existing violations.
- Policy definitions are created at the management group level (`management_group_id = var.scope`) but this module uses `azurerm_subscription_policy_assignment` for assignments. If you need management group-level assignments, extend this module.
- The `use_builtin_policies` variable has no implementation yet — it is a placeholder.

---

### fabric-capacity

**Path**: `modules/fabric-capacity`

#### Purpose

Creates a Microsoft Fabric Capacity resource. Fabric Capacity is a compute unit for Microsoft Fabric (Power BI Premium Gen2 successor), providing analytical workload capacity for workspaces. At least one Fabric admin member (by UPN) must be specified.

#### Inputs

| Variable | Type | Required | Default | Description |
|---|---|---|---|---|
| `name` | `string` | Yes | — | Fabric capacity name. 3–63 chars, lowercase alphanumeric and hyphens. |
| `resource_group_name` | `string` | Yes | — | Resource group to deploy into. |
| `location` | `string` | Yes | — | Azure region. |
| `sku` | `string` | Yes | — | SKU name. One of: `F2`, `F4`, `F8`, `F16`, `F32`, `F64`, `F128`, `F256`, `F512`, `F1024`, `F2048`. |
| `admin_members` | `list(string)` | Yes | — | List of Fabric admin UPNs (e.g., `["admin@contoso.com"]`). |
| `tags` | `map(string)` | No | `{}` | Tags to apply. |

**SKU sizing guide:**

| SKU | CUs | Typical use |
|---|---|---|
| `F2` | 2 | Development, testing |
| `F4` | 4 | Small teams, light workloads |
| `F8` | 8 | Medium workloads |
| `F16` | 16 | Larger teams or concurrent loads |
| `F32`+ | 32+ | Enterprise, heavy data engineering |

#### Outputs

| Output | Description |
|---|---|
| `id` | Fabric capacity ARM resource ID |
| `name` | Fabric capacity name |
| `sku` | SKU name |
| `admin_members` | List of admin UPNs |
| `resource_group_name` | Resource group name |

#### Usage Examples

**Minimal (dev):**

```hcl
module "fabric_capacity" {
  source              = "../modules/fabric-capacity"
  name                = "fc-platform-dev-eus2"
  resource_group_name = module.resource_group.name
  location            = var.location
  sku                 = "F2"
  admin_members       = ["platform-admin@contoso.com"]
}
```

**Production-grade:**

```hcl
module "fabric_capacity" {
  source              = "../modules/fabric-capacity"
  name                = module.naming.fabric_capacity
  resource_group_name = module.resource_group.name
  location            = var.location
  sku                 = "F32"
  admin_members       = [
    "platform-admin@contoso.com",
    "data-lead@contoso.com",
  ]
  tags = local.common_tags
}
```

#### Dependencies

- `resource-group`

#### Gotchas

- Fabric Capacity is billed continuously while provisioned. Unlike Power BI Embedded, there is no built-in pause/resume via Terraform. Implement a scheduled runbook or Azure Automation to pause capacity during off-hours to reduce costs.
- The `sku` cannot be upgraded in-place in all cases. Test SKU changes in dev first.
- `admin_members` takes UPNs (email-format usernames), not object IDs. The users must exist in the Entra ID directory associated with the subscription.
- Fabric Capacity availability varies by region. Verify `azurerm_fabric_capacity` is supported in your target region before planning.

---

## Composing Modules for a Complete Environment

A real environment deployment composes all 14 modules. Follow this pattern in your root module (`environments/dev/main.tf`, etc.):

### 1. Establish Foundation (names, group, observability)

```hcl
data "azurerm_client_config" "current" {}
data "azurerm_subscription" "current" {}

module "naming" {
  source      = "../../modules/naming"
  project     = var.project
  environment = var.environment
  location    = var.location
  unique_seed = data.azurerm_subscription.current.subscription_id
}

module "resource_group" {
  source   = "../../modules/resource-group"
  name     = module.naming.resource_group
  location = var.location
  tags     = local.common_tags
}

module "log_analytics" {
  source              = "../../modules/log-analytics"
  name                = module.naming.log_analytics_workspace
  resource_group_name = module.resource_group.name
  location            = var.location
  retention_in_days   = var.log_retention_days
  tags                = local.common_tags
}
```

### 2. Create Identities

```hcl
module "aks_identity" {
  source              = "../../modules/managed-identity"
  name                = "${module.naming.managed_identity}-aks"
  resource_group_name = module.resource_group.name
  location            = var.location
  tags                = local.common_tags
}
```

### 3. Build Networking (VNet → NSGs → Subnets)

Always create NSGs before subnets so you can pass the NSG ID during subnet creation.

```hcl
module "vnet" {
  source                     = "../../modules/virtual-network"
  name                       = module.naming.virtual_network
  resource_group_name        = module.resource_group.name
  location                   = var.location
  address_space              = [var.vnet_cidr]
  log_analytics_workspace_id = module.log_analytics.id
  tags                       = local.common_tags
}

module "nsg_aks" {
  source                     = "../../modules/network-security-group"
  name                       = "${module.naming.network_security_group}-aks"
  resource_group_name        = module.resource_group.name
  location                   = var.location
  log_analytics_workspace_id = module.log_analytics.id
  tags                       = local.common_tags
}

module "nsg_pe" {
  source              = "../../modules/network-security-group"
  name                = "${module.naming.network_security_group}-pe"
  resource_group_name = module.resource_group.name
  location            = var.location
  tags                = local.common_tags
}

module "subnet_aks" {
  source               = "../../modules/subnet"
  name                 = "snet-aks"
  resource_group_name  = module.resource_group.name
  virtual_network_name = module.vnet.name
  address_prefixes     = [var.aks_subnet_cidr]
  network_security_group_id = module.nsg_aks.id
}

module "subnet_pe" {
  source               = "../../modules/subnet"
  name                 = "snet-pe"
  resource_group_name  = module.resource_group.name
  virtual_network_name = module.vnet.name
  address_prefixes     = [var.pe_subnet_cidr]
  private_endpoint_network_policies = "Disabled"
  network_security_group_id = module.nsg_pe.id
}
```

### 4. Create PaaS Services

```hcl
module "key_vault" {
  source                     = "../../modules/key-vault"
  name                       = module.naming.key_vault
  resource_group_name        = module.resource_group.name
  location                   = var.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  log_analytics_workspace_id = module.log_analytics.id
  tags                       = local.common_tags
}

module "storage_account" {
  source              = "../../modules/storage-account"
  name                = module.naming.storage_account
  resource_group_name = module.resource_group.name
  location            = var.location
  log_analytics_workspace_id = module.log_analytics.id
  tags                = local.common_tags
}
```

### 5. Add Private Endpoints

```hcl
module "pe_key_vault" {
  source              = "../../modules/private-endpoint"
  name                = "${module.naming.private_endpoint}-kv"
  resource_group_name = module.resource_group.name
  location            = var.location
  subnet_id           = module.subnet_pe.id
  private_connection_resource_id = module.key_vault.id
  subresource_names              = ["vault"]
  tags                           = local.common_tags
}

module "pe_storage" {
  source              = "../../modules/private-endpoint"
  name                = "${module.naming.private_endpoint}-st"
  resource_group_name = module.resource_group.name
  location            = var.location
  subnet_id           = module.subnet_pe.id
  private_connection_resource_id = module.storage_account.id
  subresource_names              = ["blob"]
  tags                           = local.common_tags
}
```

### 6. Create AKS

```hcl
module "aks_cluster" {
  source              = "../../modules/aks-cluster"
  name                = module.naming.aks_cluster
  resource_group_name = module.resource_group.name
  location            = var.location
  dns_prefix          = "${var.project}-${var.environment}"

  user_assigned_identity_id  = module.aks_identity.id
  log_analytics_workspace_id = module.log_analytics.id

  default_node_pool = {
    vnet_subnet_id = module.subnet_aks.id
  }

  tags = local.common_tags
}
```

### 7. Wire RBAC

```hcl
module "rbac" {
  source = "../../modules/rbac-assignment"

  role_assignments = {
    aks_kv_secrets = {
      scope                = module.key_vault.id
      role_definition_name = "Key Vault Secrets User"
      principal_id         = module.aks_identity.principal_id
      description          = "AKS reads Key Vault secrets"
    }
    aks_storage_blob = {
      scope                = module.storage_account.id
      role_definition_name = "Storage Blob Data Contributor"
      principal_id         = module.aks_identity.principal_id
      description          = "AKS writes to blob storage"
    }
  }
}
```

### 8. Apply Governance

```hcl
module "policy" {
  source = "../../modules/azure-policy"
  scope  = data.azurerm_subscription.current.id
  # ... policy definitions and assignments
}
```

---

## Complete End-to-End Example

The following is a self-contained, production-grade root module wiring all 14 modules together. Save this as `environments/prod/main.tf`.

```hcl
# environments/prod/main.tf

terraform {
  required_version = ">= 1.6"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  backend "azurerm" {
    resource_group_name  = "rg-tfstate-prod"
    storage_account_name = "sttfstateprod"
    container_name       = "tfstate"
    key                  = "prod.terraform.tfstate"
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }
  }
}

# -----------------------------------------------------------------------
# Data sources
# -----------------------------------------------------------------------

data "azurerm_client_config" "current" {}
data "azurerm_subscription" "current" {}

# -----------------------------------------------------------------------
# Local values
# -----------------------------------------------------------------------

locals {
  project     = "platform"
  environment = "prod"
  location    = "eastus2"

  common_tags = {
    project     = local.project
    environment = local.environment
    managed_by  = "terraform"
    cost_center = "platform-engineering"
  }

  # Network CIDR plan
  vnet_cidr       = "10.0.0.0/16"
  aks_subnet_cidr = "10.0.0.0/22"   # /22 = 1022 usable IPs for AKS nodes + pods
  svc_subnet_cidr = "10.0.4.0/24"   # services subnet
  pe_subnet_cidr  = "10.0.5.0/24"   # private endpoints subnet
}

# -----------------------------------------------------------------------
# 1. Naming
# -----------------------------------------------------------------------

module "naming" {
  source = "../../modules/naming"

  project     = local.project
  environment = local.environment
  location    = local.location
  unique_seed = data.azurerm_subscription.current.subscription_id
}

# -----------------------------------------------------------------------
# 2. Resource Group
# -----------------------------------------------------------------------

module "resource_group" {
  source   = "../../modules/resource-group"
  name     = module.naming.resource_group
  location = local.location
  tags     = local.common_tags
}

# -----------------------------------------------------------------------
# 3. Log Analytics (deploy early so all other modules can send diagnostics)
# -----------------------------------------------------------------------

module "log_analytics" {
  source              = "../../modules/log-analytics"
  name                = module.naming.log_analytics_workspace
  resource_group_name = module.resource_group.name
  location            = local.location
  sku                 = "PerGB2018"
  retention_in_days   = 365
  daily_quota_gb      = 50
  tags                = local.common_tags
}

# -----------------------------------------------------------------------
# 4. Managed Identities
# -----------------------------------------------------------------------

module "aks_identity" {
  source              = "../../modules/managed-identity"
  name                = "${module.naming.managed_identity}-aks"
  resource_group_name = module.resource_group.name
  location            = local.location
  tags                = merge(local.common_tags, { workload = "aks" })
}

module "storage_identity" {
  source              = "../../modules/managed-identity"
  name                = "${module.naming.managed_identity}-storage"
  resource_group_name = module.resource_group.name
  location            = local.location
  tags                = merge(local.common_tags, { workload = "storage-cmk" })
}

# -----------------------------------------------------------------------
# 5. Virtual Network
# -----------------------------------------------------------------------

module "vnet" {
  source              = "../../modules/virtual-network"
  name                = module.naming.virtual_network
  resource_group_name = module.resource_group.name
  location            = local.location
  address_space       = [local.vnet_cidr]

  log_analytics_workspace_id = module.log_analytics.id
  tags                       = local.common_tags
}

# -----------------------------------------------------------------------
# 6. Network Security Groups
# -----------------------------------------------------------------------

module "nsg_aks" {
  source              = "../../modules/network-security-group"
  name                = "${module.naming.network_security_group}-aks"
  resource_group_name = module.resource_group.name
  location            = local.location

  security_rules = [
    {
      name                       = "AllowAzureLoadBalancer"
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "AzureLoadBalancer"
      destination_address_prefix = "*"
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
    },
  ]

  log_analytics_workspace_id = module.log_analytics.id
  tags                       = local.common_tags
}

module "nsg_pe" {
  source              = "../../modules/network-security-group"
  name                = "${module.naming.network_security_group}-pe"
  resource_group_name = module.resource_group.name
  location            = local.location
  # No rules → module applies DenyAllInbound at priority 4096
  log_analytics_workspace_id = module.log_analytics.id
  tags                       = local.common_tags
}

# -----------------------------------------------------------------------
# 7. Subnets
# -----------------------------------------------------------------------

module "subnet_aks" {
  source               = "../../modules/subnet"
  name                 = "snet-aks"
  resource_group_name  = module.resource_group.name
  virtual_network_name = module.vnet.name
  address_prefixes     = [local.aks_subnet_cidr]
  network_security_group_id = module.nsg_aks.id
}

module "subnet_services" {
  source               = "../../modules/subnet"
  name                 = "snet-services"
  resource_group_name  = module.resource_group.name
  virtual_network_name = module.vnet.name
  address_prefixes     = [local.svc_subnet_cidr]
  service_endpoints    = ["Microsoft.KeyVault", "Microsoft.Storage"]
  network_security_group_id = module.nsg_aks.id
}

module "subnet_pe" {
  source               = "../../modules/subnet"
  name                 = "snet-pe"
  resource_group_name  = module.resource_group.name
  virtual_network_name = module.vnet.name
  address_prefixes     = [local.pe_subnet_cidr]
  private_endpoint_network_policies = "Disabled"
  network_security_group_id = module.nsg_pe.id
}

# -----------------------------------------------------------------------
# 8. Key Vault
# -----------------------------------------------------------------------

module "key_vault" {
  source              = "../../modules/key-vault"
  name                = module.naming.key_vault
  resource_group_name = module.resource_group.name
  location            = local.location
  tenant_id           = data.azurerm_client_config.current.tenant_id

  sku_name                      = "premium"
  purge_protection_enabled      = true
  soft_delete_retention_days    = 90
  public_network_access_enabled = false

  network_acls_default_action             = "Deny"
  network_acls_virtual_network_subnet_ids = [module.subnet_services.id]

  log_analytics_workspace_id = module.log_analytics.id
  tags                       = local.common_tags
}

# -----------------------------------------------------------------------
# 9. Storage Account
# -----------------------------------------------------------------------

module "storage_account" {
  source              = "../../modules/storage-account"
  name                = module.naming.storage_account
  resource_group_name = module.resource_group.name
  location            = local.location

  account_tier             = "Standard"
  account_replication_type = "ZRS"

  public_network_access_enabled = false
  shared_access_key_enabled     = false

  containers = {
    data    = { access_type = "private" }
    archive = { access_type = "private" }
  }

  lifecycle_rules = [
    {
      name                       = "tiering"
      tier_to_cool_after_days    = 30
      tier_to_archive_after_days = 90
      delete_after_days          = 2555  # 7 years
    }
  ]

  log_analytics_workspace_id = module.log_analytics.id
  tags                       = local.common_tags
}

# -----------------------------------------------------------------------
# 10. Private Endpoints
# -----------------------------------------------------------------------

resource "azurerm_private_dns_zone" "key_vault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = module.resource_group.name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "key_vault" {
  name                  = "kv-dns-link"
  resource_group_name   = module.resource_group.name
  private_dns_zone_name = azurerm_private_dns_zone.key_vault.name
  virtual_network_id    = module.vnet.id
}

resource "azurerm_private_dns_zone" "blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = module.resource_group.name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "blob" {
  name                  = "blob-dns-link"
  resource_group_name   = module.resource_group.name
  private_dns_zone_name = azurerm_private_dns_zone.blob.name
  virtual_network_id    = module.vnet.id
}

module "pe_key_vault" {
  source              = "../../modules/private-endpoint"
  name                = "${module.naming.private_endpoint}-kv"
  resource_group_name = module.resource_group.name
  location            = local.location
  subnet_id           = module.subnet_pe.id

  private_connection_resource_id = module.key_vault.id
  subresource_names              = ["vault"]
  private_dns_zone_ids           = [azurerm_private_dns_zone.key_vault.id]
  tags                           = local.common_tags
}

module "pe_storage_blob" {
  source              = "../../modules/private-endpoint"
  name                = "${module.naming.private_endpoint}-blob"
  resource_group_name = module.resource_group.name
  location            = local.location
  subnet_id           = module.subnet_pe.id

  private_connection_resource_id = module.storage_account.id
  subresource_names              = ["blob"]
  private_dns_zone_ids           = [azurerm_private_dns_zone.blob.id]
  tags                           = local.common_tags
}

# -----------------------------------------------------------------------
# 11. AKS Cluster
# -----------------------------------------------------------------------

module "aks_cluster" {
  source              = "../../modules/aks-cluster"
  name                = module.naming.aks_cluster
  resource_group_name = module.resource_group.name
  location            = local.location
  dns_prefix          = "${local.project}-${local.environment}"
  kubernetes_version  = "1.30"
  sku_tier            = "Standard"

  identity_type             = "UserAssigned"
  user_assigned_identity_id = module.aks_identity.id

  default_node_pool = {
    name                         = "system"
    vm_size                      = "Standard_D2s_v3"
    min_count                    = 2
    max_count                    = 5
    os_disk_size_gb              = 50
    os_sku                       = "AzureLinux"
    zones                        = ["1", "2", "3"]
    only_critical_addons_enabled = true
    vnet_subnet_id               = module.subnet_aks.id
  }

  additional_node_pools = {
    workload = {
      vm_size         = "Standard_D4s_v3"
      min_count       = 2
      max_count       = 20
      os_disk_size_gb = 50
      os_sku          = "AzureLinux"
      zones           = ["1", "2", "3"]
      mode            = "User"
      node_labels     = { workload = "application" }
      vnet_subnet_id  = module.subnet_aks.id
    }
  }

  network_plugin      = "azure"
  network_plugin_mode = "overlay"
  network_policy      = "azure"
  service_cidr        = "172.16.0.0/16"
  dns_service_ip      = "172.16.0.10"

  oidc_issuer_enabled       = true
  workload_identity_enabled = true
  azure_policy_enabled      = true

  azure_active_directory_role_based_access_control = {
    admin_group_object_ids = [var.aks_admin_group_id]
    azure_rbac_enabled     = true
  }

  maintenance_window = {
    allowed = [
      { day = "Saturday", hours = [0, 1, 2, 3, 4] },
      { day = "Sunday",   hours = [0, 1, 2, 3, 4] },
    ]
  }

  log_analytics_workspace_id = module.log_analytics.id
  tags                       = local.common_tags
}

# -----------------------------------------------------------------------
# 12. RBAC Assignments
# -----------------------------------------------------------------------

module "rbac" {
  source = "../../modules/rbac-assignment"

  role_assignments = {
    # AKS control plane manages VNet, load balancers, route tables
    aks_network_contributor = {
      scope                = module.vnet.id
      role_definition_name = "Network Contributor"
      principal_id         = module.aks_identity.principal_id
      description          = "AKS manages load balancers and routes in VNet"
    }

    # AKS reads secrets from Key Vault
    aks_kv_secrets_user = {
      scope                = module.key_vault.id
      role_definition_name = "Key Vault Secrets User"
      principal_id         = module.aks_identity.principal_id
      description          = "AKS workload identity reads KV secrets"
    }

    # AKS writes to blob storage
    aks_storage_blob_contributor = {
      scope                = module.storage_account.id
      role_definition_name = "Storage Blob Data Contributor"
      principal_id         = module.aks_identity.principal_id
      description          = "AKS workloads read/write blob storage"
    }

    # Storage identity accesses Key Vault for CMK (if using CMK)
    storage_identity_kv_crypto = {
      scope                = module.key_vault.id
      role_definition_name = "Key Vault Crypto Service Encryption User"
      principal_id         = module.storage_identity.principal_id
      description          = "Storage account CMK encryption via Key Vault"
    }
  }
}

# -----------------------------------------------------------------------
# 13. Azure Policy (Governance)
# -----------------------------------------------------------------------

module "governance_policy" {
  source = "../../modules/azure-policy"
  scope  = data.azurerm_subscription.current.id

  policy_definitions = {
    deny-public-storage = {
      display_name = "Deny public blob access on storage accounts"
      mode         = "All"
      policy_rule = jsonencode({
        if = {
          allOf = [
            { field = "type", equals = "Microsoft.Storage/storageAccounts" },
            { field = "Microsoft.Storage/storageAccounts/allowBlobPublicAccess", notEquals = "false" }
          ]
        }
        then = { effect = "deny" }
      })
    }
    require-tags = {
      display_name = "Require environment tag on all resources"
      policy_rule = jsonencode({
        if   = { field = "tags['environment']", exists = "false" }
        then = { effect = "deny" }
      })
    }
  }

  policy_assignments = {
    deny-public-storage = {
      policy_definition_id = module.governance_policy.policy_definition_ids["deny-public-storage"]
      display_name         = "Deny public storage accounts"
      scope                = data.azurerm_subscription.current.id
      enforce              = true
    }
    require-tags = {
      policy_definition_id = module.governance_policy.policy_definition_ids["require-tags"]
      display_name         = "Require environment tag"
      scope                = data.azurerm_subscription.current.id
      enforce              = true
    }
  }
}

# -----------------------------------------------------------------------
# 14. Microsoft Fabric Capacity
# -----------------------------------------------------------------------

module "fabric_capacity" {
  source              = "../../modules/fabric-capacity"
  name                = module.naming.fabric_capacity
  resource_group_name = module.resource_group.name
  location            = local.location
  sku                 = "F8"
  admin_members       = var.fabric_admin_upns
  tags                = local.common_tags
}
```

---

## Best Practices for Module Consumption

### 1. Always Use the naming Module

Never hardcode resource names. Derive all names from `module.naming.*` outputs. This ensures:
- Names are consistent across environments.
- Names comply with Azure character limits and naming conventions.
- Storage account names are globally unique with the hash suffix.

```hcl
# Correct
name = module.naming.key_vault

# Avoid
name = "my-kv-prod"
```

### 2. Pass Tags Uniformly

Define a `common_tags` local in each root module and merge it with resource-specific tags:

```hcl
locals {
  common_tags = {
    project     = var.project
    environment = var.environment
    managed_by  = "terraform"
  }
}

# In each module call:
tags = merge(local.common_tags, { component = "networking" })
```

### 3. Wire log_analytics_workspace_id Everywhere

Every module that supports `log_analytics_workspace_id` should receive it. This enables a single workspace to capture diagnostics from every resource in the environment:

```hcl
log_analytics_workspace_id = module.log_analytics.id
```

Do not leave this empty in production environments.

### 4. Use Outputs to Create Implicit Dependencies

Terraform tracks dependencies through output references. When you write:

```hcl
resource_group_name = module.resource_group.name
```

Terraform knows to create the resource group before the dependent resource. This is safer and more readable than `depends_on`, which should be reserved for cases where outputs are not involved (e.g., an RBAC assignment must exist before a deployment but the deployment does not reference the RBAC assignment's output).

### 5. One Module Instance Per Distinct Resource

Do not reuse a single module call to manage multiple resources of the same type. Instead, instantiate the module multiple times with different configurations:

```hcl
# Correct: separate module calls for distinct subnets
module "subnet_aks" { ... }
module "subnet_pe"  { ... }

# Avoid: trying to make one module call manage many subnets
```

### 6. Pin Module Sources and Provider Versions

In production, pin both the module source version and provider versions:

```hcl
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}
```

Using local paths (`source = "../../modules/naming"`) is appropriate within a mono-repo. If modules are published to a registry, use a specific version tag.

### 7. Separate Sensitive Outputs

Outputs marked `sensitive = true` (`primary_shared_key`, `kube_config_raw`, `host`, `primary_connection_string`) are hidden from plan/apply output but still stored in state. Protect your state files by:
- Using Azure Storage with RBAC and soft-delete as the backend.
- Restricting who can run `terraform state pull`.
- Not passing sensitive outputs to non-sensitive module inputs.

### 8. Use Separate Module Calls for RBAC

Define all role assignments in one or a small number of `rbac-assignment` module calls rather than scattering `azurerm_role_assignment` resources across the codebase. This makes it easy to audit who has access to what.

### 9. Validate Before Applying

All modules include `validation` blocks on their variables. Run `terraform validate` and `terraform plan` in CI before merging to catch misconfigured inputs (wrong environment name, invalid CIDR, out-of-range retention days) before they reach `apply`.

### 10. Environment Separation

Each environment (`dev`, `staging`, `prod`) should have its own root module under `environments/` with its own Terraform state. Use variable files (`terraform.tfvars`) per environment to supply differing values (CIDR ranges, retention periods, node pool sizes, SKUs) while keeping the module calls identical.

```
environments/
  dev/
    main.tf
    variables.tf
    terraform.tfvars
  staging/
    main.tf
    variables.tf
    terraform.tfvars
  prod/
    main.tf
    variables.tf
    terraform.tfvars
```

This enforces environment parity: the same modules, the same structure, different variable values.
