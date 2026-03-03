resource "azurerm_role_assignment" "this" {
  for_each = var.role_assignments

  scope                = each.value.scope
  role_definition_name = each.value.role_definition_name
  principal_id         = each.value.principal_id
  principal_type       = each.value.principal_type
  description          = each.value.description

  lifecycle {
    precondition {
      condition     = each.value.role_definition_name != "Owner" || can(regex("EXCEPTION-APPROVED", each.value.description))
      error_message = "Owner role assignments require 'EXCEPTION-APPROVED' in the description field."
    }
  }
}

resource "azurerm_role_definition" "this" {
  for_each = var.custom_role_definitions

  name        = each.value.name
  scope       = each.value.scope
  description = each.value.description

  permissions {
    actions          = each.value.permissions.actions
    not_actions      = each.value.permissions.not_actions
    data_actions     = each.value.permissions.data_actions
    not_data_actions = each.value.permissions.not_data_actions
  }

  assignable_scopes = each.value.assignable_scopes
}
