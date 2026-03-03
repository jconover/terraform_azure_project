output "id" {
  description = "The ID of the Fabric capacity"
  value       = azurerm_fabric_capacity.this.id
}

output "name" {
  description = "The name of the Fabric capacity"
  value       = azurerm_fabric_capacity.this.name
}

output "sku" {
  description = "The SKU of the Fabric capacity"
  value       = azurerm_fabric_capacity.this.sku[0].name
}

output "admin_members" {
  description = "The administration members of the Fabric capacity"
  value       = azurerm_fabric_capacity.this.administration_members
}

output "resource_group_name" {
  description = "The resource group name of the Fabric capacity"
  value       = azurerm_fabric_capacity.this.resource_group_name
}
