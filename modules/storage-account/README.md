<!-- BEGIN_TF_DOCS -->
# Storage Account Module

Creates an Azure Storage Account with security hardening, network access controls, blob lifecycle management, and optional Customer-Managed Key encryption.

## Features

- **Security Hardened**: HTTPS-only, TLS 1.2, shared key disabled (RBAC preferred), public access disabled by default
- **Network ACLs**: Default deny with configurable IP and subnet allowlists
- **Blob Protection**: Soft delete for blobs and containers, versioning enabled by default
- **Lifecycle Management**: Configurable rules for blob tiering and deletion
- **Customer-Managed Keys**: Optional CMK encryption via Key Vault
- **Diagnostic Settings**: Optional Log Analytics integration for metrics

## Usage

```hcl
module "storage_account" {
  source = "../../modules/storage-account"

  name                = "myappdeveus2sa"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  containers = {
    data = { access_type = "private" }
  }

  lifecycle_rules = [
    {
      name                    = "blob-tiering"
      tier_to_cool_after_days = 30
      delete_after_days       = 365
    }
  ]

  log_analytics_workspace_id = module.log_analytics.id

  tags = var.tags
}
```
<!-- END_TF_DOCS -->
