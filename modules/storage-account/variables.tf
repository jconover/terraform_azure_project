variable "name" {
  description = "Name of the Storage Account"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.name))
    error_message = "Storage Account name must be 3-24 characters, lowercase alphanumeric only (no hyphens)."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group where the Storage Account will be created"
  type        = string
}

variable "location" {
  description = "Azure region for the Storage Account"
  type        = string
}

variable "account_tier" {
  description = "Performance tier of the Storage Account (Standard or Premium)"
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Standard", "Premium"], var.account_tier)
    error_message = "Account tier must be one of: Standard, Premium."
  }
}

variable "account_replication_type" {
  description = "Replication type for the Storage Account"
  type        = string
  default     = "LRS"

  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.account_replication_type)
    error_message = "Account replication type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "account_kind" {
  description = "Kind of the Storage Account"
  type        = string
  default     = "StorageV2"
}

variable "min_tls_version" {
  description = "Minimum TLS version for the Storage Account"
  type        = string
  default     = "TLS1_2"
}

variable "https_traffic_only_enabled" {
  description = "Whether only HTTPS traffic is allowed"
  type        = bool
  default     = true
}

variable "public_network_access_enabled" {
  description = "Whether public network access is enabled for the Storage Account"
  type        = bool
  default     = false
}

variable "shared_access_key_enabled" {
  description = "Whether shared access key authentication is enabled (prefer RBAC)"
  type        = bool
  default     = false
}

variable "blob_soft_delete_retention_days" {
  description = "Number of days to retain soft-deleted blobs"
  type        = number
  default     = 30

  validation {
    condition     = var.blob_soft_delete_retention_days >= 1 && var.blob_soft_delete_retention_days <= 365
    error_message = "Blob soft delete retention days must be between 1 and 365."
  }
}

variable "container_soft_delete_retention_days" {
  description = "Number of days to retain soft-deleted containers"
  type        = number
  default     = 30

  validation {
    condition     = var.container_soft_delete_retention_days >= 1 && var.container_soft_delete_retention_days <= 365
    error_message = "Container soft delete retention days must be between 1 and 365."
  }
}

variable "versioning_enabled" {
  description = "Whether blob versioning is enabled"
  type        = bool
  default     = true
}

variable "network_rules_default_action" {
  description = "Default action for network rules (Allow or Deny)"
  type        = string
  default     = "Deny"
}

variable "network_rules_ip_rules" {
  description = "List of IP addresses or CIDR blocks allowed to access the Storage Account"
  type        = list(string)
  default     = []
}

variable "network_rules_virtual_network_subnet_ids" {
  description = "List of virtual network subnet IDs allowed to access the Storage Account"
  type        = list(string)
  default     = []
}

variable "network_rules_bypass" {
  description = "List of services to bypass network rules"
  type        = list(string)
  default     = ["AzureServices"]
}

variable "containers" {
  description = "Map of storage containers to create"
  type = map(object({
    access_type = optional(string, "private")
  }))
  default = {}
}

variable "lifecycle_rules" {
  description = "List of lifecycle management rules for blob storage"
  type = list(object({
    name                       = string
    enabled                    = optional(bool, true)
    prefix_match               = optional(list(string), [])
    tier_to_cool_after_days    = optional(number, null)
    tier_to_archive_after_days = optional(number, null)
    delete_after_days          = optional(number, null)
  }))
  default = []
}

variable "cmk_key_vault_key_id" {
  description = "Key Vault Key ID for Customer-Managed Key encryption"
  type        = string
  default     = ""
}

variable "cmk_user_assigned_identity_id" {
  description = "User Assigned Identity ID for Customer-Managed Key access"
  type        = string
  default     = ""
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

variable "tags" {
  description = "Tags to apply to the Storage Account"
  type        = map(string)
  default     = {}
}
