<!-- BEGIN_TF_DOCS -->
# Managed Identity Module

Creates an Azure User-Assigned Managed Identity with configurable naming, location, and tags.

## Usage

```hcl
module "managed_identity" {
  source = "../../modules/managed-identity"

  name                = "id-platform-dev-eus2"
  resource_group_name = "rg-platform-dev-eus2"
  location            = "eastus2"

  tags = {
    environment = "dev"
    project     = "platform"
  }
}
```
<!-- END_TF_DOCS -->
