variable "subscription_id" {
  description = "Azure subscription ID where the storage account exists"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group containing the storage account"
  type        = string
  default     = "rg-legacy"
}

variable "storage_account_name" {
  description = "Name of the existing storage account to import"
  type        = string
  default     = "stlegacydata"
}

variable "location" {
  description = "Azure region of the existing storage account"
  type        = string
  default     = "eastus2"
}
