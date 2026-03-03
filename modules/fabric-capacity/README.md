<!-- BEGIN_TF_DOCS -->
# Fabric Capacity Module

Creates a Microsoft Fabric capacity resource with configurable SKU and administration members.

## Usage

```hcl
module "fabric_capacity" {
  source = "../../modules/fabric-capacity"

  name                = "fc-analytics-dev-eus2"
  resource_group_name = "rg-platform-dev-eus2"
  location            = "eastus2"
  sku                 = "F2"
  admin_members       = ["admin@contoso.com"]

  tags = {
    environment = "dev"
    project     = "analytics"
  }
}
```
<!-- END_TF_DOCS -->

## Fabric Automation Scope

### What Terraform CAN manage

- **Fabric capacity resource** (`azurerm_fabric_capacity`) — provisioning, SKU scaling, admin member assignment, tagging, and lifecycle management
- **RBAC assignments** — Azure role assignments for service principals on the Fabric capacity resource using `azurerm_role_assignment`

### What Terraform CANNOT manage

- **Fabric workspace items** — lakehouses, warehouses, pipelines, notebooks, dataflows, semantic models, and reports are not supported by the AzureRM provider
- **Workspace creation and configuration** — Fabric workspaces themselves are not an AzureRM resource
- **Data pipeline orchestration** — Fabric Data Factory pipelines cannot be authored or managed via Terraform
- **Capacity assignment to workspaces** — assigning a capacity to a workspace is a Fabric API operation, not an ARM operation

### Workarounds for unsupported resources

- **REST API** — the [Microsoft Fabric REST API](https://learn.microsoft.com/en-us/rest/api/fabric/core) supports workspace and item management; use `terraform_data` with provisioners or external scripts
- **PowerShell** — the `MicrosoftPowerBIMgmt` module provides cmdlets for Fabric and Power BI workspace administration
- **Azure CLI extensions** — experimental Fabric extensions may become available as the platform matures

### Provider maturity note

The `azurerm_fabric_capacity` resource is relatively new in the AzureRM provider. Check the [provider changelog](https://github.com/hashicorp/terraform-provider-azurerm/blob/main/CHANGELOG.md) for updates on additional Fabric resource support.
