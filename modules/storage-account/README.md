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
| [azurerm_monitor_diagnostic_setting.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_diagnostic_setting) | resource |
| [azurerm_storage_account.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_account) | resource |
| [azurerm_storage_container.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_container) | resource |
| [azurerm_storage_management_policy.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_management_policy) | resource |
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_account_kind"></a> [account\_kind](#input\_account\_kind) | Kind of the Storage Account | `string` | `"StorageV2"` | no |
| <a name="input_account_replication_type"></a> [account\_replication\_type](#input\_account\_replication\_type) | Replication type for the Storage Account | `string` | `"LRS"` | no |
| <a name="input_account_tier"></a> [account\_tier](#input\_account\_tier) | Performance tier of the Storage Account (Standard or Premium) | `string` | `"Standard"` | no |
| <a name="input_blob_soft_delete_retention_days"></a> [blob\_soft\_delete\_retention\_days](#input\_blob\_soft\_delete\_retention\_days) | Number of days to retain soft-deleted blobs | `number` | `30` | no |
| <a name="input_cmk_key_vault_key_id"></a> [cmk\_key\_vault\_key\_id](#input\_cmk\_key\_vault\_key\_id) | Key Vault Key ID for Customer-Managed Key encryption | `string` | `""` | no |
| <a name="input_cmk_user_assigned_identity_id"></a> [cmk\_user\_assigned\_identity\_id](#input\_cmk\_user\_assigned\_identity\_id) | User Assigned Identity ID for Customer-Managed Key access | `string` | `""` | no |
| <a name="input_container_soft_delete_retention_days"></a> [container\_soft\_delete\_retention\_days](#input\_container\_soft\_delete\_retention\_days) | Number of days to retain soft-deleted containers | `number` | `30` | no |
| <a name="input_containers"></a> [containers](#input\_containers) | Map of storage containers to create | <pre>map(object({<br>    access_type = optional(string, "private")<br>  }))</pre> | `{}` | no |
| <a name="input_enable_diagnostics"></a> [enable\_diagnostics](#input\_enable\_diagnostics) | Whether to create diagnostic settings. Use this instead of checking log\_analytics\_workspace\_id to avoid unknown-value issues at plan time. | `bool` | `false` | no |
| <a name="input_https_traffic_only_enabled"></a> [https\_traffic\_only\_enabled](#input\_https\_traffic\_only\_enabled) | Whether only HTTPS traffic is allowed | `bool` | `true` | no |
| <a name="input_lifecycle_rules"></a> [lifecycle\_rules](#input\_lifecycle\_rules) | List of lifecycle management rules for blob storage | <pre>list(object({<br>    name                       = string<br>    enabled                    = optional(bool, true)<br>    prefix_match               = optional(list(string), [])<br>    tier_to_cool_after_days    = optional(number, null)<br>    tier_to_archive_after_days = optional(number, null)<br>    delete_after_days          = optional(number, null)<br>  }))</pre> | `[]` | no |
| <a name="input_location"></a> [location](#input\_location) | Azure region for the Storage Account | `string` | n/a | yes |
| <a name="input_log_analytics_workspace_id"></a> [log\_analytics\_workspace\_id](#input\_log\_analytics\_workspace\_id) | Log Analytics workspace ID for diagnostic settings. Required when enable\_diagnostics is true. | `string` | `null` | no |
| <a name="input_min_tls_version"></a> [min\_tls\_version](#input\_min\_tls\_version) | Minimum TLS version for the Storage Account | `string` | `"TLS1_2"` | no |
| <a name="input_name"></a> [name](#input\_name) | Name of the Storage Account | `string` | n/a | yes |
| <a name="input_network_rules_bypass"></a> [network\_rules\_bypass](#input\_network\_rules\_bypass) | List of services to bypass network rules | `list(string)` | <pre>[<br>  "AzureServices"<br>]</pre> | no |
| <a name="input_network_rules_default_action"></a> [network\_rules\_default\_action](#input\_network\_rules\_default\_action) | Default action for network rules (Allow or Deny) | `string` | `"Deny"` | no |
| <a name="input_network_rules_ip_rules"></a> [network\_rules\_ip\_rules](#input\_network\_rules\_ip\_rules) | List of IP addresses or CIDR blocks allowed to access the Storage Account | `list(string)` | `[]` | no |
| <a name="input_network_rules_virtual_network_subnet_ids"></a> [network\_rules\_virtual\_network\_subnet\_ids](#input\_network\_rules\_virtual\_network\_subnet\_ids) | List of virtual network subnet IDs allowed to access the Storage Account | `list(string)` | `[]` | no |
| <a name="input_public_network_access_enabled"></a> [public\_network\_access\_enabled](#input\_public\_network\_access\_enabled) | Whether public network access is enabled for the Storage Account | `bool` | `false` | no |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Name of the resource group where the Storage Account will be created | `string` | n/a | yes |
| <a name="input_shared_access_key_enabled"></a> [shared\_access\_key\_enabled](#input\_shared\_access\_key\_enabled) | Whether shared access key authentication is enabled (prefer RBAC) | `bool` | `false` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to the Storage Account | `map(string)` | `{}` | no |
| <a name="input_versioning_enabled"></a> [versioning\_enabled](#input\_versioning\_enabled) | Whether blob versioning is enabled | `bool` | `true` | no |
## Outputs

| Name | Description |
|------|-------------|
| <a name="output_id"></a> [id](#output\_id) | The ID of the Storage Account |
| <a name="output_name"></a> [name](#output\_name) | The name of the Storage Account |
| <a name="output_primary_blob_endpoint"></a> [primary\_blob\_endpoint](#output\_primary\_blob\_endpoint) | The primary blob endpoint of the Storage Account |
| <a name="output_primary_connection_string"></a> [primary\_connection\_string](#output\_primary\_connection\_string) | The primary connection string of the Storage Account |
| <a name="output_resource_group_name"></a> [resource\_group\_name](#output\_resource\_group\_name) | The name of the resource group containing the Storage Account |
<!-- END_TF_DOCS -->
