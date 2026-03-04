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
| [azurerm_virtual_network.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_network) | resource |
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_address_space"></a> [address\_space](#input\_address\_space) | List of address spaces (CIDR blocks) for the virtual network | `list(string)` | n/a | yes |
| <a name="input_dns_servers"></a> [dns\_servers](#input\_dns\_servers) | List of custom DNS server IP addresses | `list(string)` | `[]` | no |
| <a name="input_enable_diagnostics"></a> [enable\_diagnostics](#input\_enable\_diagnostics) | Whether to create diagnostic settings. Use this instead of checking log\_analytics\_workspace\_id to avoid unknown-value issues at plan time. | `bool` | `false` | no |
| <a name="input_location"></a> [location](#input\_location) | Azure region for the virtual network | `string` | n/a | yes |
| <a name="input_log_analytics_workspace_id"></a> [log\_analytics\_workspace\_id](#input\_log\_analytics\_workspace\_id) | Log Analytics Workspace ID for diagnostic settings. Required when enable\_diagnostics is true. | `string` | `null` | no |
| <a name="input_name"></a> [name](#input\_name) | Name of the virtual network | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Name of the resource group where the virtual network will be created | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Map of tags to apply to the virtual network | `map(string)` | `{}` | no |
## Outputs

| Name | Description |
|------|-------------|
| <a name="output_address_space"></a> [address\_space](#output\_address\_space) | The address space of the virtual network |
| <a name="output_id"></a> [id](#output\_id) | The ID of the virtual network |
| <a name="output_name"></a> [name](#output\_name) | The name of the virtual network |
| <a name="output_resource_group_name"></a> [resource\_group\_name](#output\_resource\_group\_name) | The name of the resource group containing the virtual network |
<!-- END_TF_DOCS -->
