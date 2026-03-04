terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

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
  description = "Key attributes of the deployed user-assigned managed identity including its ID, principal ID, client ID, tenant ID, and name."
  value = {
    id           = module.managed_identity.id
    principal_id = module.managed_identity.principal_id
    client_id    = module.managed_identity.client_id
    tenant_id    = module.managed_identity.tenant_id
    name         = module.managed_identity.name
  }
}
