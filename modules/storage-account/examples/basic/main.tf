terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

module "storage_account" {
  source = "../../"

  name                = "myappdeveus2sa"
  resource_group_name = "myapp-dev-eus2-rg"
  location            = "eastus2"

  public_network_access_enabled = false
  shared_access_key_enabled     = false

  containers = {
    data = {
      access_type = "private"
    }
  }

  lifecycle_rules = [
    {
      name                       = "blob-tiering"
      prefix_match               = []
      tier_to_cool_after_days    = 30
      tier_to_archive_after_days = 90
      delete_after_days          = 365
    }
  ]

  tags = {
    Environment = "dev"
    Project     = "myapp"
  }
}

output "storage_account" {
  description = "Key attributes of the deployed storage account including its ID, name, and primary blob endpoint."
  value = {
    id                    = module.storage_account.id
    name                  = module.storage_account.name
    primary_blob_endpoint = module.storage_account.primary_blob_endpoint
  }
}
