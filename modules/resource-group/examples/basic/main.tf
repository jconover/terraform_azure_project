terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

module "resource_group" {
  source = "../../"

  name     = "rg-platform-dev-eus2"
  location = "eastus2"

  tags = {
    environment = "dev"
    project     = "platform"
    managed_by  = "terraform"
  }
}

output "resource_group" {
  description = "Key attributes of the deployed resource group including its ID, name, and location."
  value = {
    id       = module.resource_group.id
    name     = module.resource_group.name
    location = module.resource_group.location
  }
}
