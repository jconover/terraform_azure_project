output "id" {
  description = "The ID of the Key Vault"
  value       = azurerm_key_vault.this.id
}

output "name" {
  description = "The name of the Key Vault"
  value       = azurerm_key_vault.this.name
}

output "vault_uri" {
  description = "The URI of the Key Vault"
  value       = azurerm_key_vault.this.vault_uri
}

output "tenant_id" {
  description = "The Azure AD tenant ID of the Key Vault"
  value       = azurerm_key_vault.this.tenant_id
}

output "resource_group_name" {
  description = "The name of the resource group containing the Key Vault"
  value       = azurerm_key_vault.this.resource_group_name
}
