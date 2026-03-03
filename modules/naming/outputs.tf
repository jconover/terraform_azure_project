output "base_name" {
  description = "Base name prefix: {project}-{environment}-{location_short}"
  value       = local.base_name
}

output "location_short" {
  description = "Abbreviated location code"
  value       = local.location_short
}

output "resource_group" {
  description = "Generated name for Azure Resource Group"
  value       = local.standard_names["resource_group"]
}

output "virtual_network" {
  description = "Generated name for Azure Virtual Network"
  value       = local.standard_names["virtual_network"]
}

output "subnet" {
  description = "Generated name for Azure Subnet"
  value       = local.standard_names["subnet"]
}

output "network_security_group" {
  description = "Generated name for Azure Network Security Group"
  value       = local.standard_names["network_security_group"]
}

output "public_ip" {
  description = "Generated name for Azure Public IP"
  value       = local.standard_names["public_ip"]
}

output "private_endpoint" {
  description = "Generated name for Azure Private Endpoint"
  value       = local.standard_names["private_endpoint"]
}

output "key_vault" {
  description = "Generated name for Azure Key Vault (max 24 chars)"
  value       = local.key_vault_name
}

output "storage_account" {
  description = "Generated name for Azure Storage Account (max 24 chars, no hyphens)"
  value       = local.storage_name
}

output "aks_cluster" {
  description = "Generated name for Azure Kubernetes Service cluster"
  value       = local.standard_names["aks_cluster"]
}

output "log_analytics_workspace" {
  description = "Generated name for Azure Log Analytics Workspace"
  value       = local.standard_names["log_analytics"]
}

output "managed_identity" {
  description = "Generated name for Azure Managed Identity"
  value       = local.standard_names["managed_identity"]
}

output "fabric_capacity" {
  description = "Generated name for Microsoft Fabric Capacity"
  value       = local.standard_names["fabric_capacity"]
}
