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
  value = {
    id       = module.resource_group.id
    name     = module.resource_group.name
    location = module.resource_group.location
  }
}
