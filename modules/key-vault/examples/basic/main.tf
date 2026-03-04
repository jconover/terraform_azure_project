terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

module "key_vault" {
  source = "../../"

  name                = "myapp-dev-eus2-kv"
  resource_group_name = "myapp-dev-eus2-rg"
  location            = "eastus2"
  tenant_id           = "00000000-0000-0000-0000-000000000000"

  tags = {
    Environment = "dev"
    Project     = "myapp"
  }
}

output "key_vault" {
  description = "Key attributes of the deployed Azure Key Vault including its ID, name, and URI."
  value = {
    id        = module.key_vault.id
    name      = module.key_vault.name
    vault_uri = module.key_vault.vault_uri
  }
}
