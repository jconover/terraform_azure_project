variable "name" {
  description = "Name of the virtual network"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group where the virtual network will be created"
  type        = string
}

variable "location" {
  description = "Azure region for the virtual network"
  type        = string
}

variable "address_space" {
  description = "List of address spaces (CIDR blocks) for the virtual network"
  type        = list(string)

  validation {
    condition     = length(var.address_space) > 0
    error_message = "At least one CIDR block must be provided in address_space."
  }
}

variable "dns_servers" {
  description = "List of custom DNS server IP addresses"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Map of tags to apply to the virtual network"
  type        = map(string)
  default     = {}
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics Workspace ID for diagnostic settings. If empty, diagnostic settings are not created."
  type        = string
  default     = ""
}
