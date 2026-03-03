variable "name" {
  description = "Name of the resource group"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9._()-]{1,90}$", var.name))
    error_message = "Resource group name must be 1-90 characters and can only contain alphanumerics, underscores, parentheses, hyphens, and periods."
  }
}

variable "location" {
  description = "Azure region for the resource group"
  type        = string

  validation {
    condition = contains([
      "eastus", "eastus2", "westus", "westus2", "westus3",
      "centralus", "northcentralus", "southcentralus",
      "northeurope", "westeurope", "uksouth", "ukwest",
      "southeastasia", "eastasia", "australiaeast", "australiasoutheast",
      "japaneast", "japanwest", "koreacentral", "canadacentral",
      "brazilsouth", "francecentral", "germanywestcentral",
      "norwayeast", "switzerlandnorth", "swedencentral",
    ], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "tags" {
  description = "Map of tags to assign to the resource group"
  type        = map(string)
  default     = {}
}

variable "prevent_destroy" {
  description = "Enable prevent_destroy lifecycle protection"
  type        = bool
  default     = false
}
