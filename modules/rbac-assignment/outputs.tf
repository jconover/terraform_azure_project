output "role_assignment_ids" {
  description = "Map of role assignment name to ID"
  value       = { for k, v in azurerm_role_assignment.this : k => v.id }
}

output "custom_role_definition_ids" {
  description = "Map of custom role definition name to ID"
  value       = { for k, v in azurerm_role_definition.this : k => v.role_definition_resource_id }
}
