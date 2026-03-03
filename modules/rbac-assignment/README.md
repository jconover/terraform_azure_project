<!-- BEGIN_TF_DOCS -->
# RBAC Assignment Module

Manages Azure role assignments and custom role definitions with governance guardrails.

## Features

- **Role Assignments**: Create role assignments with principal type support
- **Custom Role Definitions**: Define custom roles with fine-grained permissions
- **Owner Guardrail**: Blocks Owner role assignments unless explicitly approved via description

## Usage

```hcl
module "rbac_assignment" {
  source = "../../modules/rbac-assignment"

  role_assignments = {
    reader = {
      scope                = "/subscriptions/00000000-0000-0000-0000-000000000000"
      role_definition_name = "Reader"
      principal_id         = "11111111-1111-1111-1111-111111111111"
    }
  }
}
```
<!-- END_TF_DOCS -->
