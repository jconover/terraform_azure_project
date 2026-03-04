variable "name" {
  description = "Name of the network security group"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region for the network security group"
  type        = string
}

variable "security_rules" {
  description = "List of security rules to apply to the NSG"
  type = list(object({
    name                       = string
    priority                   = number
    direction                  = string
    access                     = string
    protocol                   = string
    source_port_range          = string
    destination_port_range     = string
    source_address_prefix      = string
    destination_address_prefix = string
  }))
  default = []
}

variable "tags" {
  description = "Tags to apply to the network security group"
  type        = map(string)
  default     = {}
}

variable "enable_diagnostics" {
  description = "Whether to create diagnostic settings. Use this instead of checking log_analytics_workspace_id to avoid unknown-value issues at plan time."
  type        = bool
  default     = false
}

variable "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace for diagnostic settings. Required when enable_diagnostics is true."
  type        = string
  default     = null
}
