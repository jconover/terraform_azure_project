<!-- BEGIN_TF_DOCS -->


## Usage

```hcl
module "example" {
  source = "../path/to/module"
  # see inputs below
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | ~> 4.0 |
## Providers

| Name | Version |
|------|---------|
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | 4.62.1 |
## Resources

| Name | Type |
|------|------|
| [azurerm_kubernetes_cluster.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster) | resource |
| [azurerm_kubernetes_cluster_node_pool.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster_node_pool) | resource |
| [azurerm_monitor_diagnostic_setting.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_diagnostic_setting) | resource |
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_additional_node_pools"></a> [additional\_node\_pools](#input\_additional\_node\_pools) | Map of additional node pools to create | <pre>map(object({<br>    vm_size         = optional(string, "Standard_B2s")<br>    min_count       = optional(number, 1)<br>    max_count       = optional(number, 3)<br>    os_disk_size_gb = optional(number, 30)<br>    os_sku          = optional(string, "AzureLinux")<br>    zones           = optional(list(string), ["1", "2", "3"])<br>    max_pods        = optional(number, 30)<br>    mode            = optional(string, "User")<br>    node_labels     = optional(map(string), {})<br>    node_taints     = optional(list(string), [])<br>    vnet_subnet_id  = optional(string, null)<br>  }))</pre> | `{}` | no |
| <a name="input_azure_active_directory_role_based_access_control"></a> [azure\_active\_directory\_role\_based\_access\_control](#input\_azure\_active\_directory\_role\_based\_access\_control) | Azure AD RBAC configuration for the AKS cluster | <pre>object({<br>    admin_group_object_ids = optional(list(string), [])<br>    azure_rbac_enabled     = optional(bool, true)<br>  })</pre> | `{}` | no |
| <a name="input_azure_policy_enabled"></a> [azure\_policy\_enabled](#input\_azure\_policy\_enabled) | Enable Azure Policy for the AKS cluster | `bool` | `true` | no |
| <a name="input_default_node_pool"></a> [default\_node\_pool](#input\_default\_node\_pool) | Configuration for the default (system) node pool | <pre>object({<br>    name                         = optional(string, "system")<br>    vm_size                      = optional(string, "Standard_B2s")<br>    min_count                    = optional(number, 1)<br>    max_count                    = optional(number, 3)<br>    os_disk_size_gb              = optional(number, 30)<br>    os_sku                       = optional(string, "AzureLinux")<br>    zones                        = optional(list(string), ["1", "2", "3"])<br>    max_pods                     = optional(number, 30)<br>    only_critical_addons_enabled = optional(bool, true)<br>    vnet_subnet_id               = optional(string, null)<br>  })</pre> | `{}` | no |
| <a name="input_dns_prefix"></a> [dns\_prefix](#input\_dns\_prefix) | DNS prefix for the AKS cluster | `string` | n/a | yes |
| <a name="input_dns_service_ip"></a> [dns\_service\_ip](#input\_dns\_service\_ip) | IP address for the Kubernetes DNS service | `string` | `"172.16.0.10"` | no |
| <a name="input_enable_diagnostics"></a> [enable\_diagnostics](#input\_enable\_diagnostics) | Whether to create diagnostic settings and enable OMS agent. Use this instead of checking log\_analytics\_workspace\_id to avoid unknown-value issues at plan time. | `bool` | `false` | no |
| <a name="input_identity_type"></a> [identity\_type](#input\_identity\_type) | Type of managed identity for the AKS cluster | `string` | `"UserAssigned"` | no |
| <a name="input_kubernetes_version"></a> [kubernetes\_version](#input\_kubernetes\_version) | Kubernetes version. Uses latest if null. | `string` | `null` | no |
| <a name="input_location"></a> [location](#input\_location) | Azure region for the AKS cluster | `string` | n/a | yes |
| <a name="input_log_analytics_workspace_id"></a> [log\_analytics\_workspace\_id](#input\_log\_analytics\_workspace\_id) | Log Analytics workspace ID for monitoring. Required when enable\_diagnostics is true. | `string` | `null` | no |
| <a name="input_maintenance_window"></a> [maintenance\_window](#input\_maintenance\_window) | Maintenance window configuration for the AKS cluster | <pre>object({<br>    allowed = optional(list(object({<br>      day   = string<br>      hours = list(number)<br>    })), [{ day = "Sunday", hours = [0, 1, 2, 3] }])<br>  })</pre> | `{}` | no |
| <a name="input_name"></a> [name](#input\_name) | Name of the AKS cluster | `string` | n/a | yes |
| <a name="input_network_plugin"></a> [network\_plugin](#input\_network\_plugin) | Network plugin for the AKS cluster | `string` | `"azure"` | no |
| <a name="input_network_plugin_mode"></a> [network\_plugin\_mode](#input\_network\_plugin\_mode) | Network plugin mode for the AKS cluster | `string` | `"overlay"` | no |
| <a name="input_network_policy"></a> [network\_policy](#input\_network\_policy) | Network policy for the AKS cluster | `string` | `"azure"` | no |
| <a name="input_oidc_issuer_enabled"></a> [oidc\_issuer\_enabled](#input\_oidc\_issuer\_enabled) | Enable OIDC issuer for workload identity | `bool` | `true` | no |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Name of the resource group where the AKS cluster will be created | `string` | n/a | yes |
| <a name="input_role_based_access_control_enabled"></a> [role\_based\_access\_control\_enabled](#input\_role\_based\_access\_control\_enabled) | Enable Kubernetes RBAC | `bool` | `true` | no |
| <a name="input_service_cidr"></a> [service\_cidr](#input\_service\_cidr) | CIDR range for Kubernetes services | `string` | `"172.16.0.0/16"` | no |
| <a name="input_sku_tier"></a> [sku\_tier](#input\_sku\_tier) | AKS SKU tier | `string` | `"Standard"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to the AKS cluster | `map(string)` | `{}` | no |
| <a name="input_user_assigned_identity_id"></a> [user\_assigned\_identity\_id](#input\_user\_assigned\_identity\_id) | ID of the user-assigned managed identity. Required when identity\_type is UserAssigned. | `string` | `""` | no |
| <a name="input_workload_identity_enabled"></a> [workload\_identity\_enabled](#input\_workload\_identity\_enabled) | Enable workload identity for the AKS cluster | `bool` | `true` | no |
## Outputs

| Name | Description |
|------|-------------|
| <a name="output_fqdn"></a> [fqdn](#output\_fqdn) | The FQDN of the AKS cluster |
| <a name="output_host"></a> [host](#output\_host) | The Kubernetes cluster server host |
| <a name="output_id"></a> [id](#output\_id) | The ID of the AKS cluster |
| <a name="output_kube_config_raw"></a> [kube\_config\_raw](#output\_kube\_config\_raw) | Raw Kubernetes config for the AKS cluster |
| <a name="output_kubelet_identity"></a> [kubelet\_identity](#output\_kubelet\_identity) | The kubelet managed identity of the AKS cluster |
| <a name="output_name"></a> [name](#output\_name) | The name of the AKS cluster |
| <a name="output_node_resource_group"></a> [node\_resource\_group](#output\_node\_resource\_group) | The name of the auto-generated resource group for AKS node resources |
| <a name="output_oidc_issuer_url"></a> [oidc\_issuer\_url](#output\_oidc\_issuer\_url) | The OIDC issuer URL of the AKS cluster |
<!-- END_TF_DOCS -->
