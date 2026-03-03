variable "name" {
  description = "Name for the managed identity"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group where the identity will be created"
  type        = string
}

variable "location" {
  description = "Azure region for the managed identity"
  type        = string
}

variable "type" {
  description = "Type of managed identity to create"
  type        = string
  default     = "UserAssigned"

  validation {
    condition     = contains(["UserAssigned", "SystemAssigned"], var.type)
    error_message = "Identity type must be either 'UserAssigned' or 'SystemAssigned'."
  }
}

variable "tags" {
  description = "Map of tags to assign to the managed identity"
  type        = map(string)
  default     = {}
}
