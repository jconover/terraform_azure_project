<!-- BEGIN_TF_DOCS -->
# Azure Policy Module

Manages Azure Policy definitions and assignments for governance.

## Features

- **Custom Policy Definitions**: Create custom policies with JSON policy rules
- **Policy Assignments**: Assign policies to subscriptions with configurable enforcement
- **Built-in Policy Support**: Optional integration with Azure built-in policies
- **Managed Identity**: Optional managed identity for policies requiring remediation

## Usage

```hcl
module "azure_policy" {
  source = "../../modules/azure-policy"

  scope = "/providers/Microsoft.Management/managementGroups/my-mg"

  policy_definitions = {
    require-tags = {
      display_name = "Require environment tag"
      policy_rule  = jsonencode({
        if = {
          field  = "[concat('tags[', 'environment', ']')]"
          exists = "false"
        }
        then = {
          effect = "deny"
        }
      })
    }
  }
}
```
<!-- END_TF_DOCS -->
