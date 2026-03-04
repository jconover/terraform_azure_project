variable "name" {
  description = "Name of the Key Vault"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{1,24}$", var.name))
    error_message = "Key Vault name must be max 24 characters, alphanumeric and hyphens only."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group where the Key Vault will be created"
  type        = string
}

variable "location" {
  description = "Azure region for the Key Vault"
  type        = string
}

variable "sku_name" {
  description = "SKU name for the Key Vault (standard or premium)"
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "premium"], var.sku_name)
    error_message = "SKU name must be one of: standard, premium."
  }
}

variable "tenant_id" {
  description = "Azure Active Directory tenant ID for the Key Vault"
  type        = string
}

variable "rbac_authorization_enabled" {
  description = "Enable RBAC authorization for the Key Vault (recommended over access policies)"
  type        = bool
  default     = true
}

variable "purge_protection_enabled" {
  description = "Enable purge protection to prevent permanent deletion during retention period"
  type        = bool
  default     = true
}

variable "soft_delete_retention_days" {
  description = "Number of days to retain soft-deleted vaults and vault objects"
  type        = number
  default     = 90

  validation {
    condition     = var.soft_delete_retention_days >= 7 && var.soft_delete_retention_days <= 90
    error_message = "Soft delete retention days must be between 7 and 90."
  }
}

variable "public_network_access_enabled" {
  description = "Whether public network access is enabled for the Key Vault"
  type        = bool
  default     = false
}

variable "network_acls_default_action" {
  description = "Default action for network ACLs (Allow or Deny)"
  type        = string
  default     = "Deny"
}

variable "network_acls_ip_rules" {
  description = "List of IP addresses or CIDR blocks allowed to access the Key Vault"
  type        = list(string)
  default     = []
}

variable "network_acls_virtual_network_subnet_ids" {
  description = "List of virtual network subnet IDs allowed to access the Key Vault"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to the Key Vault"
  type        = map(string)
  default     = {}
}

variable "enable_diagnostics" {
  description = "Whether to create diagnostic settings. Use this instead of checking log_analytics_workspace_id to avoid unknown-value issues at plan time."
  type        = bool
  default     = false
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID for diagnostic settings. Required when enable_diagnostics is true."
  type        = string
  default     = null
}
