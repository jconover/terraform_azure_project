variable "name" {
  description = "Name of the Fabric capacity"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,63}$", var.name))
    error_message = "Name must be 3-63 characters, lowercase alphanumeric and hyphens only."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group to deploy the Fabric capacity into"
  type        = string
}

variable "location" {
  description = "Azure region for the Fabric capacity"
  type        = string
}

variable "sku" {
  description = "SKU name for the Fabric capacity"
  type        = string

  validation {
    condition = contains([
      "F2", "F4", "F8", "F16", "F32", "F64", "F128",
      "F256", "F512", "F1024", "F2048",
    ], var.sku)
    error_message = "SKU must be one of: F2, F4, F8, F16, F32, F64, F128, F256, F512, F1024, F2048."
  }
}

variable "admin_members" {
  description = "List of UPNs for Fabric capacity administrators"
  type        = list(string)
}

variable "tags" {
  description = "Map of tags to assign to the Fabric capacity"
  type        = map(string)
  default     = {}
}
