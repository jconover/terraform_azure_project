terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

module "subnet" {
  source = "../../"

  name                 = "snet-app-dev"
  resource_group_name  = "rg-platform-dev-eus2"
  virtual_network_name = "vnet-platform-dev-eus2"
  address_prefixes     = ["10.0.1.0/24"]
}

output "subnet" {
  description = "Key attributes of the deployed subnet including its ID, name, and address prefixes."
  value = {
    id               = module.subnet.id
    name             = module.subnet.name
    address_prefixes = module.subnet.address_prefixes
  }
}
