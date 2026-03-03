output "id" {
  description = "The ID of the network security group"
  value       = azurerm_network_security_group.this.id
}

output "name" {
  description = "The name of the network security group"
  value       = azurerm_network_security_group.this.name
}

output "resource_group_name" {
  description = "The name of the resource group"
  value       = azurerm_network_security_group.this.resource_group_name
}
