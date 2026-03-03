module "rbac_assignment" {
  source = "../../"

  role_assignments = {
    reader = {
      scope                = "/subscriptions/00000000-0000-0000-0000-000000000000"
      role_definition_name = "Reader"
      principal_id         = "11111111-1111-1111-1111-111111111111"
      principal_type       = "ServicePrincipal"
      description          = "Platform service read access"
    }
    contributor = {
      scope                = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/myapp-dev-rg"
      role_definition_name = "Contributor"
      principal_id         = "22222222-2222-2222-2222-222222222222"
      principal_type       = "Group"
      description          = "Dev team contributor access to resource group"
    }
  }

  custom_role_definitions = {
    platform_contributor = {
      name        = "Platform Contributor"
      scope       = "/subscriptions/00000000-0000-0000-0000-000000000000"
      description = "Contributor with guardrails blocking dangerous operations"
      permissions = {
        actions = ["*"]
        not_actions = [
          "Microsoft.Authorization/roleAssignments/write",
          "Microsoft.Authorization/roleAssignments/delete",
          "Microsoft.Authorization/*/Delete",
          "Microsoft.Authorization/elevateAccess/Action",
        ]
      }
      assignable_scopes = [
        "/subscriptions/00000000-0000-0000-0000-000000000000"
      ]
    }
  }
}

output "role_assignments" {
  value = module.rbac_assignment.role_assignment_ids
}

output "custom_roles" {
  value = module.rbac_assignment.custom_role_definition_ids
}
