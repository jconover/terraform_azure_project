<!-- BEGIN_TF_DOCS -->
# AKS Cluster Module

Creates a production-grade Azure Kubernetes Service (AKS) cluster with autoscaling, workload identity, and Azure CNI Overlay networking.

## Features

- **Managed Identity**: UserAssigned or SystemAssigned identity support
- **Autoscaling**: Default and additional node pools with min/max autoscaling
- **Azure CNI Overlay**: Network plugin with overlay mode and configurable network policy
- **Workload Identity**: OIDC issuer and workload identity enabled by default
- **Azure Policy**: Enabled by default for cluster governance
- **Azure AD RBAC**: Integrated Azure Active Directory role-based access control
- **Maintenance Windows**: Configurable maintenance window schedules
- **Diagnostic Settings**: Optional Log Analytics integration for cluster monitoring

## Usage

```hcl
module "aks_cluster" {
  source = "../../modules/aks-cluster"

  name                = module.naming.aks_cluster
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  dns_prefix          = "myapp-dev"

  identity_type             = "UserAssigned"
  user_assigned_identity_id = azurerm_user_assigned_identity.aks.id

  log_analytics_workspace_id = module.log_analytics.id

  tags = var.tags
}
```

## Out of Scope

The following are intentionally out of scope for this module and may be added as future extension points:

- **Service Mesh**: Istio, Linkerd, or Open Service Mesh integration
- **GitOps**: Flux or ArgoCD bootstrapping
- **Custom Node Images**: Custom VHD or shared image gallery references
- **GPU Node Pools**: GPU-specific VM sizes and NVIDIA device plugin configuration
<!-- END_TF_DOCS -->
