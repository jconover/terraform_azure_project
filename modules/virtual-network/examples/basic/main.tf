terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

module "virtual_network" {
  source = "../../"

  name                = "platform-dev-eus2-vnet"
  resource_group_name = "platform-dev-eus2-rg"
  location            = "eastus2"
  address_space       = ["10.0.0.0/16"]

  tags = {
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

output "vnet" {
  description = "Key attributes of the deployed virtual network including its ID, name, and address space."
  value = {
    id            = module.virtual_network.id
    name          = module.virtual_network.name
    address_space = module.virtual_network.address_space
  }
}
