variable "subscription_id" {
  description = "Azure subscription ID where the networking resources exist"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group containing the networking resources"
  type        = string
  default     = "rg-legacy"
}

variable "location" {
  description = "Azure region of the existing resources"
  type        = string
  default     = "eastus2"
}

variable "vnet_name" {
  description = "Name of the existing virtual network to import"
  type        = string
  default     = "vnet-legacy"
}

variable "address_space" {
  description = "Address space of the existing virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "subnet_app_name" {
  description = "Name of the application tier subnet"
  type        = string
  default     = "snet-app"
}

variable "subnet_data_name" {
  description = "Name of the data tier subnet"
  type        = string
  default     = "snet-data"
}

variable "nsg_name" {
  description = "Name of the existing network security group to import"
  type        = string
  default     = "nsg-legacy"
}
