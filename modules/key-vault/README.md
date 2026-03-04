<!-- BEGIN_TF_DOCS -->


## Usage

```hcl
module "example" {
  source = "../path/to/module"
  # see inputs below
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | ~> 4.0 |
## Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | 4.62.1 |
## Resources

| Name | Type |
|------|------|
| [azurerm_key_vault.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault) | resource |
| [azurerm_monitor_diagnostic_setting.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_diagnostic_setting) | resource |
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_enable_diagnostics"></a> [enable\_diagnostics](#input\_enable\_diagnostics) | Whether to create diagnostic settings. Use this instead of checking log\_analytics\_workspace\_id to avoid unknown-value issues at plan time. | `bool` | `false` | no |
| <a name="input_location"></a> [location](#input\_location) | Azure region for the Key Vault | `string` | n/a | yes |
| <a name="input_log_analytics_workspace_id"></a> [log\_analytics\_workspace\_id](#input\_log\_analytics\_workspace\_id) | Log Analytics workspace ID for diagnostic settings. Required when enable\_diagnostics is true. | `string` | `null` | no |
| <a name="input_name"></a> [name](#input\_name) | Name of the Key Vault | `string` | n/a | yes |
| <a name="input_network_acls_default_action"></a> [network\_acls\_default\_action](#input\_network\_acls\_default\_action) | Default action for network ACLs (Allow or Deny) | `string` | `"Deny"` | no |
| <a name="input_network_acls_ip_rules"></a> [network\_acls\_ip\_rules](#input\_network\_acls\_ip\_rules) | List of IP addresses or CIDR blocks allowed to access the Key Vault | `list(string)` | `[]` | no |
| <a name="input_network_acls_virtual_network_subnet_ids"></a> [network\_acls\_virtual\_network\_subnet\_ids](#input\_network\_acls\_virtual\_network\_subnet\_ids) | List of virtual network subnet IDs allowed to access the Key Vault | `list(string)` | `[]` | no |
| <a name="input_public_network_access_enabled"></a> [public\_network\_access\_enabled](#input\_public\_network\_access\_enabled) | Whether public network access is enabled for the Key Vault | `bool` | `false` | no |
| <a name="input_purge_protection_enabled"></a> [purge\_protection\_enabled](#input\_purge\_protection\_enabled) | Enable purge protection to prevent permanent deletion during retention period | `bool` | `true` | no |
| <a name="input_rbac_authorization_enabled"></a> [rbac\_authorization\_enabled](#input\_rbac\_authorization\_enabled) | Enable RBAC authorization for the Key Vault (recommended over access policies) | `bool` | `true` | no |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Name of the resource group where the Key Vault will be created | `string` | n/a | yes |
| <a name="input_sku_name"></a> [sku\_name](#input\_sku\_name) | SKU name for the Key Vault (standard or premium) | `string` | `"standard"` | no |
| <a name="input_soft_delete_retention_days"></a> [soft\_delete\_retention\_days](#input\_soft\_delete\_retention\_days) | Number of days to retain soft-deleted vaults and vault objects | `number` | `90` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to the Key Vault | `map(string)` | `{}` | no |
| <a name="input_tenant_id"></a> [tenant\_id](#input\_tenant\_id) | Azure Active Directory tenant ID for the Key Vault | `string` | n/a | yes |
## Outputs

| Name | Description |
|------|-------------|
| <a name="output_id"></a> [id](#output\_id) | The ID of the Key Vault |
| <a name="output_name"></a> [name](#output\_name) | The name of the Key Vault |
| <a name="output_resource_group_name"></a> [resource\_group\_name](#output\_resource\_group\_name) | The name of the resource group containing the Key Vault |
| <a name="output_tenant_id"></a> [tenant\_id](#output\_tenant\_id) | The Azure AD tenant ID of the Key Vault |
| <a name="output_vault_uri"></a> [vault\_uri](#output\_vault\_uri) | The URI of the Key Vault |
<!-- END_TF_DOCS -->
