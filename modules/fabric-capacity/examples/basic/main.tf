module "fabric_capacity" {
  source = "../../"

  name                = "fc-analytics-dev-eus2"
  resource_group_name = "rg-platform-dev-eus2"
  location            = "eastus2"
  sku                 = "F2"
  admin_members       = ["admin@contoso.com"]

  tags = {
    environment = "dev"
    project     = "analytics"
    managed_by  = "terraform"
  }
}

output "fabric_capacity" {
  value = {
    id                  = module.fabric_capacity.id
    name                = module.fabric_capacity.name
    sku                 = module.fabric_capacity.sku
    admin_members       = module.fabric_capacity.admin_members
    resource_group_name = module.fabric_capacity.resource_group_name
  }
}
