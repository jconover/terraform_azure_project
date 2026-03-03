variable "name" {
  description = "Name of the subnet"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group containing the virtual network"
  type        = string
}

variable "virtual_network_name" {
  description = "Name of the virtual network to create the subnet in"
  type        = string
}

variable "address_prefixes" {
  description = "List of address prefixes for the subnet"
  type        = list(string)
}

variable "delegation" {
  description = "Delegation configuration for the subnet"
  type = object({
    name = string
    service_delegation = object({
      name    = string
      actions = list(string)
    })
  })
  default = null
}

variable "service_endpoints" {
  description = "List of service endpoints to associate with the subnet"
  type        = list(string)
  default     = []
}

variable "network_security_group_id" {
  description = "ID of the network security group to associate with the subnet"
  type        = string
  default     = ""
}

variable "private_endpoint_network_policies" {
  description = "Enable or disable network policies for private endpoints on the subnet"
  type        = string
  default     = "Enabled"
}
