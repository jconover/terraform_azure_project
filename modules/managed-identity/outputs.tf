output "id" {
  description = "The ID of the managed identity"
  value       = try(azurerm_user_assigned_identity.this[0].id, null)
}

output "principal_id" {
  description = "The service principal ID of the managed identity"
  value       = try(azurerm_user_assigned_identity.this[0].principal_id, null)
}

output "client_id" {
  description = "The client/application ID of the managed identity"
  value       = try(azurerm_user_assigned_identity.this[0].client_id, null)
}

output "tenant_id" {
  description = "The tenant ID of the managed identity"
  value       = try(azurerm_user_assigned_identity.this[0].tenant_id, null)
}

output "name" {
  description = "The name of the managed identity"
  value       = try(azurerm_user_assigned_identity.this[0].name, null)
}
