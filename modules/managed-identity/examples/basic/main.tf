module "managed_identity" {
  source = "../../"

  name                = "id-platform-dev-eus2"
  resource_group_name = "rg-platform-dev-eus2"
  location            = "eastus2"

  tags = {
    environment = "dev"
    project     = "platform"
    managed_by  = "terraform"
  }
}

output "managed_identity" {
  value = {
    id           = module.managed_identity.id
    principal_id = module.managed_identity.principal_id
    client_id    = module.managed_identity.client_id
    tenant_id    = module.managed_identity.tenant_id
    name         = module.managed_identity.name
  }
}
