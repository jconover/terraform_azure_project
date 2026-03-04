variable "name" {
  description = "Name of the AKS cluster"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group where the AKS cluster will be created"
  type        = string
}

variable "location" {
  description = "Azure region for the AKS cluster"
  type        = string
}

variable "dns_prefix" {
  description = "DNS prefix for the AKS cluster"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version. Uses latest if null."
  type        = string
  default     = null
}

variable "sku_tier" {
  description = "AKS SKU tier"
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Free", "Standard", "Premium"], var.sku_tier)
    error_message = "SKU tier must be one of: Free, Standard, Premium."
  }
}

variable "identity_type" {
  description = "Type of managed identity for the AKS cluster"
  type        = string
  default     = "UserAssigned"

  validation {
    condition     = contains(["SystemAssigned", "UserAssigned"], var.identity_type)
    error_message = "Identity type must be one of: SystemAssigned, UserAssigned."
  }
}

variable "user_assigned_identity_id" {
  description = "ID of the user-assigned managed identity. Required when identity_type is UserAssigned."
  type        = string
  default     = ""
}

variable "default_node_pool" {
  description = "Configuration for the default (system) node pool"
  type = object({
    name                         = optional(string, "system")
    vm_size                      = optional(string, "Standard_B2s")
    min_count                    = optional(number, 1)
    max_count                    = optional(number, 3)
    os_disk_size_gb              = optional(number, 30)
    os_sku                       = optional(string, "AzureLinux")
    zones                        = optional(list(string), ["1", "2", "3"])
    max_pods                     = optional(number, 30)
    only_critical_addons_enabled = optional(bool, true)
    vnet_subnet_id               = optional(string, null)
  })
  default = {}

  validation {
    condition     = var.default_node_pool.min_count >= 1
    error_message = "Default node pool min_count must be at least 1 for a system pool."
  }
}

variable "additional_node_pools" {
  description = "Map of additional node pools to create"
  type = map(object({
    vm_size         = optional(string, "Standard_B2s")
    min_count       = optional(number, 1)
    max_count       = optional(number, 3)
    os_disk_size_gb = optional(number, 30)
    os_sku          = optional(string, "AzureLinux")
    zones           = optional(list(string), ["1", "2", "3"])
    max_pods        = optional(number, 30)
    mode            = optional(string, "User")
    node_labels     = optional(map(string), {})
    node_taints     = optional(list(string), [])
    vnet_subnet_id  = optional(string, null)
  }))
  default = {}
}

variable "network_plugin" {
  description = "Network plugin for the AKS cluster"
  type        = string
  default     = "azure"
}

variable "network_plugin_mode" {
  description = "Network plugin mode for the AKS cluster"
  type        = string
  default     = "overlay"
}

variable "network_policy" {
  description = "Network policy for the AKS cluster"
  type        = string
  default     = "azure"

  validation {
    condition     = contains(["azure", "calico", "cilium"], var.network_policy)
    error_message = "Network policy must be one of: azure, calico, cilium."
  }
}

variable "service_cidr" {
  description = "CIDR range for Kubernetes services"
  type        = string
  default     = "172.16.0.0/16"
}

variable "dns_service_ip" {
  description = "IP address for the Kubernetes DNS service"
  type        = string
  default     = "172.16.0.10"
}

variable "oidc_issuer_enabled" {
  description = "Enable OIDC issuer for workload identity"
  type        = bool
  default     = true
}

variable "workload_identity_enabled" {
  description = "Enable workload identity for the AKS cluster"
  type        = bool
  default     = true
}

variable "azure_policy_enabled" {
  description = "Enable Azure Policy for the AKS cluster"
  type        = bool
  default     = true
}

variable "role_based_access_control_enabled" {
  description = "Enable Kubernetes RBAC"
  type        = bool
  default     = true
}

variable "azure_active_directory_role_based_access_control" {
  description = "Azure AD RBAC configuration for the AKS cluster"
  type = object({
    admin_group_object_ids = optional(list(string), [])
    azure_rbac_enabled     = optional(bool, true)
  })
  default = {}
}

variable "maintenance_window" {
  description = "Maintenance window configuration for the AKS cluster"
  type = object({
    allowed = optional(list(object({
      day   = string
      hours = list(number)
    })), [{ day = "Sunday", hours = [0, 1, 2, 3] }])
  })
  default = {}
}

variable "enable_diagnostics" {
  description = "Whether to create diagnostic settings and enable OMS agent. Use this instead of checking log_analytics_workspace_id to avoid unknown-value issues at plan time."
  type        = bool
  default     = false
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID for monitoring. Required when enable_diagnostics is true."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to the AKS cluster"
  type        = map(string)
  default     = {}
}
