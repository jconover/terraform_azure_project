<!-- BEGIN_TF_DOCS -->
# Key Vault Module

Creates an Azure Key Vault with RBAC authorization, purge protection, and network access controls.

## Features

- **RBAC Authorization**: Uses Azure RBAC instead of access policies (recommended)
- **Purge Protection**: Enabled by default to prevent accidental permanent deletion
- **Network ACLs**: Default deny with configurable IP and subnet allowlists
- **Diagnostic Settings**: Optional Log Analytics integration for audit logging

## Usage

```hcl
module "key_vault" {
  source = "../../modules/key-vault"

  name                = module.naming.key_vault
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tenant_id           = data.azurerm_client_config.current.tenant_id

  log_analytics_workspace_id = module.log_analytics.id

  tags = var.tags
}
```
<!-- END_TF_DOCS -->
