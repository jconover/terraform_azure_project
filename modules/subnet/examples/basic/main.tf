module "subnet" {
  source = "../../"

  name                 = "snet-app-dev"
  resource_group_name  = "rg-platform-dev-eus2"
  virtual_network_name = "vnet-platform-dev-eus2"
  address_prefixes     = ["10.0.1.0/24"]
}

output "subnet" {
  value = {
    id               = module.subnet.id
    name             = module.subnet.name
    address_prefixes = module.subnet.address_prefixes
  }
}
