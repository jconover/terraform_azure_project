terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

module "log_analytics" {
  source = "../../"

  name                = "myapp-dev-eus2-law"
  resource_group_name = "myapp-dev-eus2-rg"
  location            = "eastus2"

  retention_in_days = 30
  daily_quota_gb    = 5

  tags = {
    Environment = "dev"
    Project     = "myapp"
  }
}

output "log_analytics" {
  description = "Key attributes of the deployed Log Analytics workspace including its ID, name, and workspace ID."
  value = {
    id           = module.log_analytics.id
    name         = module.log_analytics.name
    workspace_id = module.log_analytics.workspace_id
  }
}
