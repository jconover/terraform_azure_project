<!-- BEGIN_TF_DOCS -->
# Virtual Network Module

Creates an Azure Virtual Network with optional diagnostic settings.

## Usage

```hcl
module "virtual_network" {
  source = "../../modules/virtual-network"

  name                = "platform-dev-eus2-vnet"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  address_space       = ["10.0.0.0/16"]

  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  tags = {
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}
```
<!-- END_TF_DOCS -->
