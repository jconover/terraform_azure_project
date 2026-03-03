variable "project" {
  description = "Project name used as a prefix in resource names"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,9}$", var.project))
    error_message = "Project must be 2-10 chars, lowercase alphanumeric and hyphens, starting with a letter."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "location" {
  description = "Azure region for resource deployment"
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

variable "suffix" {
  description = "Optional suffix appended to resource names for uniqueness"
  type        = string
  default     = ""
}

variable "unique_seed" {
  description = "Seed string for generating unique suffixes (e.g., subscription ID). Used for globally unique names like storage accounts."
  type        = string
  default     = ""
}
