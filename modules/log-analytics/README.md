<!-- BEGIN_TF_DOCS -->
# Log Analytics Module

Creates an Azure Log Analytics workspace for centralized logging and monitoring.

## Features

- **Configurable SKU**: Supports all Log Analytics pricing tiers
- **Retention Control**: Configurable data retention from 30 to 730 days
- **Daily Quota**: Optional daily ingestion cap to control costs

## Usage

```hcl
module "log_analytics" {
  source = "../../modules/log-analytics"

  name                = module.naming.log_analytics_workspace
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  retention_in_days = 90
  daily_quota_gb    = 10

  tags = var.tags
}
```
<!-- END_TF_DOCS -->
