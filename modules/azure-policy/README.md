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
| [azurerm_policy_definition.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/policy_definition) | resource |
| [azurerm_subscription_policy_assignment.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subscription_policy_assignment) | resource |
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_policy_assignments"></a> [policy\_assignments](#input\_policy\_assignments) | Map of policy assignments to create | <pre>map(object({<br>    policy_definition_id = string<br>    display_name         = string<br>    description          = optional(string, "")<br>    scope                = string<br>    parameters           = optional(string, "")<br>    enforce              = optional(bool, true)<br>    identity_type        = optional(string, "")<br>    location             = optional(string, "")<br>  }))</pre> | `{}` | no |
| <a name="input_policy_definitions"></a> [policy\_definitions](#input\_policy\_definitions) | Map of custom policy definitions to create | <pre>map(object({<br>    display_name = string<br>    description  = optional(string, "")<br>    mode         = optional(string, "All")<br>    policy_rule  = string<br>    metadata     = optional(string, "")<br>    parameters   = optional(string, "")<br>  }))</pre> | `{}` | no |
| <a name="input_scope"></a> [scope](#input\_scope) | Default scope for policy definitions (subscription or management group ID) | `string` | n/a | yes |
## Outputs

| Name | Description |
|------|-------------|
| <a name="output_policy_assignment_ids"></a> [policy\_assignment\_ids](#output\_policy\_assignment\_ids) | Map of policy assignment names to their IDs |
| <a name="output_policy_definition_ids"></a> [policy\_definition\_ids](#output\_policy\_definition\_ids) | Map of policy definition names to their IDs |
<!-- END_TF_DOCS -->
