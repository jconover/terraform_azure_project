<!-- BEGIN_TF_DOCS -->
# Network Security Group Module

Creates an Azure Network Security Group with dynamic security rules and optional diagnostic settings.

## Usage

```hcl
module "nsg" {
  source = "../../modules/network-security-group"

  name                = "nsg-app-dev"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

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
      destination_address_prefix = "*"
    }
  ]

  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  tags = {
    environment = "dev"
  }
}
```

## Features

- Dynamic security rule creation from variable input
- Default deny-all-inbound rule (priority 4096) when no rules are provided
- Optional Log Analytics diagnostic settings for NSG flow logs
- Tagging support
<!-- END_TF_DOCS -->
