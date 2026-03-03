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
  value = {
    id            = module.virtual_network.id
    name          = module.virtual_network.name
    address_space = module.virtual_network.address_space
  }
}
