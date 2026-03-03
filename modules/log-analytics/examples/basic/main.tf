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
  value = {
    id           = module.log_analytics.id
    name         = module.log_analytics.name
    workspace_id = module.log_analytics.workspace_id
  }
}
