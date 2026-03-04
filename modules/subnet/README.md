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
| [azurerm_subnet.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet) | resource |
| [azurerm_subnet_network_security_group_association.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_network_security_group_association) | resource |
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_address_prefixes"></a> [address\_prefixes](#input\_address\_prefixes) | List of address prefixes for the subnet | `list(string)` | n/a | yes |
| <a name="input_delegation"></a> [delegation](#input\_delegation) | Delegation configuration for the subnet | <pre>object({<br>    name = string<br>    service_delegation = object({<br>      name    = string<br>      actions = list(string)<br>    })<br>  })</pre> | `null` | no |
| <a name="input_enable_nsg_association"></a> [enable\_nsg\_association](#input\_enable\_nsg\_association) | Whether to associate an NSG with the subnet. Use this instead of checking network\_security\_group\_id to avoid unknown-value issues at plan time. | `bool` | `false` | no |
| <a name="input_name"></a> [name](#input\_name) | Name of the subnet | `string` | n/a | yes |
| <a name="input_network_security_group_id"></a> [network\_security\_group\_id](#input\_network\_security\_group\_id) | ID of the network security group to associate with the subnet. Required when enable\_nsg\_association is true. | `string` | `null` | no |
| <a name="input_private_endpoint_network_policies"></a> [private\_endpoint\_network\_policies](#input\_private\_endpoint\_network\_policies) | Enable or disable network policies for private endpoints on the subnet | `string` | `"Enabled"` | no |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Name of the resource group containing the virtual network | `string` | n/a | yes |
| <a name="input_service_endpoints"></a> [service\_endpoints](#input\_service\_endpoints) | List of service endpoints to associate with the subnet | `list(string)` | `[]` | no |
| <a name="input_virtual_network_name"></a> [virtual\_network\_name](#input\_virtual\_network\_name) | Name of the virtual network to create the subnet in | `string` | n/a | yes |
## Outputs

| Name | Description |
|------|-------------|
| <a name="output_address_prefixes"></a> [address\_prefixes](#output\_address\_prefixes) | The address prefixes for the subnet |
| <a name="output_id"></a> [id](#output\_id) | The ID of the subnet |
| <a name="output_name"></a> [name](#output\_name) | The name of the subnet |
| <a name="output_resource_group_name"></a> [resource\_group\_name](#output\_resource\_group\_name) | The name of the resource group |
| <a name="output_virtual_network_name"></a> [virtual\_network\_name](#output\_virtual\_network\_name) | The name of the virtual network |
<!-- END_TF_DOCS -->
