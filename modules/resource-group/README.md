<!-- BEGIN_TF_DOCS -->
# Resource Group Module

Creates an Azure Resource Group with configurable naming, location, tags, and lifecycle protection.

## Usage

```hcl
module "resource_group" {
  source = "../../modules/resource-group"

  name     = "rg-platform-dev-eus2"
  location = "eastus2"

  tags = {
    environment = "dev"
    project     = "platform"
  }
}
```
<!-- END_TF_DOCS -->
