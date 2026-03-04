terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

module "nsg" {
  source = "../../"

  name                = "nsg-app-dev"
  resource_group_name = "rg-platform-dev-eus2"
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
      destination_address_prefix = "*"
    }
  ]

  tags = {
    environment = "dev"
  }
}

output "nsg" {
  description = "Key attributes of the deployed network security group including its ID and name."
  value = {
    id   = module.nsg.id
    name = module.nsg.name
  }
}
