<!-- BEGIN_TF_DOCS -->
# Subnet Module

Creates an Azure Subnet with optional delegation, service endpoints, and NSG association.

## Usage

```hcl
module "subnet" {
  source = "../../modules/subnet"

  name                 = "snet-app-dev"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]

  service_endpoints         = ["Microsoft.Storage", "Microsoft.KeyVault"]
  network_security_group_id = azurerm_network_security_group.main.id

  delegation = {
    name = "app-service"
    service_delegation = {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}
```

## Features

- Subnet creation with configurable address prefixes
- Optional service endpoint association
- Optional delegation for PaaS services
- Optional NSG association
- Private endpoint network policy control
<!-- END_TF_DOCS -->
