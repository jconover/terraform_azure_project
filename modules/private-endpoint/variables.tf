variable "name" {
  description = "Name of the private endpoint"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group where the private endpoint will be created"
  type        = string
}

variable "location" {
  description = "Azure region for the private endpoint"
  type        = string
}

variable "subnet_id" {
  description = "ID of the subnet where the private endpoint will be placed"
  type        = string
}

variable "private_connection_resource_id" {
  description = "The ID of the resource to connect to via private endpoint"
  type        = string
}

variable "subresource_names" {
  description = "List of subresource names for the private endpoint connection (e.g. [\"blob\"], [\"vault\"])"
  type        = list(string)
}

variable "is_manual_connection" {
  description = "Whether the private endpoint connection requires manual approval"
  type        = bool
  default     = false
}

variable "private_dns_zone_ids" {
  description = "List of private DNS zone IDs to link with this private endpoint"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to the private endpoint"
  type        = map(string)
  default     = {}
}
