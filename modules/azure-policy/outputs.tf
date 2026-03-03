output "policy_definition_ids" {
  description = "Map of policy definition names to their IDs"
  value       = { for k, v in azurerm_policy_definition.this : k => v.id }
}

output "policy_assignment_ids" {
  description = "Map of policy assignment names to their IDs"
  value       = { for k, v in azurerm_subscription_policy_assignment.this : k => v.id }
}
