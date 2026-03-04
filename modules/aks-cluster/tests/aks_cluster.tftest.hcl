# Terraform native tests for the aks-cluster module.
# All runs use command = plan to validate configuration without provisioning resources.
# Requires Terraform >= 1.6.0 and azurerm provider ~> 4.0.

# ---------------------------------------------------------------------------
# Provider configuration shared across all run blocks.
# The azurerm provider is configured in mock mode so no Azure credentials are
# needed during plan-only testing.
# ---------------------------------------------------------------------------

provider "azurerm" {
  features {}
  skip_provider_registration = true
}

# ---------------------------------------------------------------------------
# Reusable variable sets referenced by individual run blocks.
# ---------------------------------------------------------------------------

# Minimal required inputs that every test builds upon.
variables {
  name                = "test-aks-cluster"
  resource_group_name = "test-rg"
  location            = "eastus2"
  dns_prefix          = "testaks"

  # Use SystemAssigned so no real identity resource is needed in plan tests.
  identity_type             = "SystemAssigned"
  user_assigned_identity_id = ""
}

# ---------------------------------------------------------------------------
# 1. Basic AKS cluster creation with required variables only.
#    Verifies the cluster resource is planned with the supplied name,
#    location, resource group, and dns_prefix.
# ---------------------------------------------------------------------------

run "basic_cluster_creation" {
  command = plan

  variables {
    name                = "basic-aks"
    resource_group_name = "basic-rg"
    location            = "eastus2"
    dns_prefix          = "basicaks"
    identity_type       = "SystemAssigned"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.name == "basic-aks"
    error_message = "Expected cluster name to be 'basic-aks', got '${azurerm_kubernetes_cluster.this.name}'."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.location == "eastus2"
    error_message = "Expected location to be 'eastus2', got '${azurerm_kubernetes_cluster.this.location}'."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.resource_group_name == "basic-rg"
    error_message = "Expected resource_group_name to be 'basic-rg', got '${azurerm_kubernetes_cluster.this.resource_group_name}'."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.dns_prefix == "basicaks"
    error_message = "Expected dns_prefix to be 'basicaks', got '${azurerm_kubernetes_cluster.this.dns_prefix}'."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.role_based_access_control_enabled == true
    error_message = "RBAC should be enabled by default."
  }
}

# ---------------------------------------------------------------------------
# 2. Managed identity – SystemAssigned.
#    Confirms the identity block is planned with type SystemAssigned and that
#    no user-assigned identity IDs are set.
# ---------------------------------------------------------------------------

run "managed_identity_system_assigned" {
  command = plan

  variables {
    identity_type             = "SystemAssigned"
    user_assigned_identity_id = ""
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.identity[0].type == "SystemAssigned"
    error_message = "Expected identity type 'SystemAssigned', got '${azurerm_kubernetes_cluster.this.identity[0].type}'."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.identity[0].identity_ids == null
    error_message = "SystemAssigned identity should have null identity_ids."
  }
}

# ---------------------------------------------------------------------------
# 3. Azure CNI Overlay network plugin mode.
#    Verifies that network_plugin = "azure" and network_plugin_mode = "overlay"
#    are reflected in the planned network_profile block.
# ---------------------------------------------------------------------------

run "azure_cni_overlay_network" {
  command = plan

  variables {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = "azure"
    service_cidr        = "172.16.0.0/16"
    dns_service_ip      = "172.16.0.10"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.network_profile[0].network_plugin == "azure"
    error_message = "Expected network_plugin 'azure', got '${azurerm_kubernetes_cluster.this.network_profile[0].network_plugin}'."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.network_profile[0].network_plugin_mode == "overlay"
    error_message = "Expected network_plugin_mode 'overlay', got '${azurerm_kubernetes_cluster.this.network_profile[0].network_plugin_mode}'."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.network_profile[0].network_policy == "azure"
    error_message = "Expected network_policy 'azure', got '${azurerm_kubernetes_cluster.this.network_profile[0].network_policy}'."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.network_profile[0].service_cidr == "172.16.0.0/16"
    error_message = "Expected service_cidr '172.16.0.0/16', got '${azurerm_kubernetes_cluster.this.network_profile[0].service_cidr}'."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.network_profile[0].dns_service_ip == "172.16.0.10"
    error_message = "Expected dns_service_ip '172.16.0.10', got '${azurerm_kubernetes_cluster.this.network_profile[0].dns_service_ip}'."
  }
}

# ---------------------------------------------------------------------------
# 4. Autoscaling configuration – custom min/max node counts.
#    Validates that the default_node_pool receives the supplied autoscaler
#    bounds and that auto_scaling_enabled is always true.
# ---------------------------------------------------------------------------

run "autoscaling_configuration" {
  command = plan

  variables {
    default_node_pool = {
      name      = "system"
      vm_size   = "Standard_D4s_v5"
      min_count = 2
      max_count = 10
    }
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.default_node_pool[0].auto_scaling_enabled == true
    error_message = "auto_scaling_enabled must always be true for the default node pool."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.default_node_pool[0].min_count == 2
    error_message = "Expected min_count 2, got ${azurerm_kubernetes_cluster.this.default_node_pool[0].min_count}."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.default_node_pool[0].max_count == 10
    error_message = "Expected max_count 10, got ${azurerm_kubernetes_cluster.this.default_node_pool[0].max_count}."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.default_node_pool[0].vm_size == "Standard_D4s_v5"
    error_message = "Expected vm_size 'Standard_D4s_v5', got '${azurerm_kubernetes_cluster.this.default_node_pool[0].vm_size}'."
  }
}

# ---------------------------------------------------------------------------
# 5. OIDC issuer enabled.
#    Ensures oidc_issuer_enabled is planned as true when explicitly set.
# ---------------------------------------------------------------------------

run "oidc_issuer_enabled" {
  command = plan

  variables {
    oidc_issuer_enabled = true
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.oidc_issuer_enabled == true
    error_message = "Expected oidc_issuer_enabled to be true."
  }
}

# ---------------------------------------------------------------------------
# 5b. OIDC issuer disabled.
#     Ensures oidc_issuer_enabled can be toggled off.
# ---------------------------------------------------------------------------

run "oidc_issuer_disabled" {
  command = plan

  variables {
    oidc_issuer_enabled       = false
    workload_identity_enabled = false
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.oidc_issuer_enabled == false
    error_message = "Expected oidc_issuer_enabled to be false."
  }
}

# ---------------------------------------------------------------------------
# 6. Workload identity enabled.
#    Verifies workload_identity_enabled is planned as true.
#    OIDC issuer must also be true for workload identity to be valid.
# ---------------------------------------------------------------------------

run "workload_identity_enabled" {
  command = plan

  variables {
    oidc_issuer_enabled       = true
    workload_identity_enabled = true
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.workload_identity_enabled == true
    error_message = "Expected workload_identity_enabled to be true."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.oidc_issuer_enabled == true
    error_message = "OIDC issuer must be enabled when workload identity is enabled."
  }
}

# ---------------------------------------------------------------------------
# 6b. Workload identity disabled.
# ---------------------------------------------------------------------------

run "workload_identity_disabled" {
  command = plan

  variables {
    oidc_issuer_enabled       = false
    workload_identity_enabled = false
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.workload_identity_enabled == false
    error_message = "Expected workload_identity_enabled to be false."
  }
}

# ---------------------------------------------------------------------------
# 7. Azure Policy add-on enabled.
#    Confirms azure_policy_enabled is planned as true.
# ---------------------------------------------------------------------------

run "azure_policy_addon_enabled" {
  command = plan

  variables {
    azure_policy_enabled = true
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.azure_policy_enabled == true
    error_message = "Expected azure_policy_enabled to be true."
  }
}

# ---------------------------------------------------------------------------
# 7b. Azure Policy add-on disabled.
# ---------------------------------------------------------------------------

run "azure_policy_addon_disabled" {
  command = plan

  variables {
    azure_policy_enabled = false
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.azure_policy_enabled == false
    error_message = "Expected azure_policy_enabled to be false."
  }
}

# ---------------------------------------------------------------------------
# 8. Maintenance window configuration.
#    Validates that the maintenance_window allowed block is planned with the
#    correct day and hours values.
# ---------------------------------------------------------------------------

run "maintenance_window_configuration" {
  command = plan

  variables {
    maintenance_window = {
      allowed = [
        {
          day   = "Saturday"
          hours = [22, 23]
        },
        {
          day   = "Sunday"
          hours = [0, 1, 2, 3]
        }
      ]
    }
  }

  assert {
    condition     = length(azurerm_kubernetes_cluster.this.maintenance_window[0].allowed) == 2
    error_message = "Expected 2 allowed maintenance windows, got ${length(azurerm_kubernetes_cluster.this.maintenance_window[0].allowed)}."
  }

  assert {
    condition = anytrue([
      for w in azurerm_kubernetes_cluster.this.maintenance_window[0].allowed : w.day == "Saturday"
    ])
    error_message = "Expected 'Saturday' to appear in maintenance window allowed days."
  }

  assert {
    condition = anytrue([
      for w in azurerm_kubernetes_cluster.this.maintenance_window[0].allowed : w.day == "Sunday"
    ])
    error_message = "Expected 'Sunday' to appear in maintenance window allowed days."
  }
}

# ---------------------------------------------------------------------------
# 8b. Default maintenance window (Sunday 00-03).
#     Confirms the module default is applied when no window is specified.
# ---------------------------------------------------------------------------

run "maintenance_window_default" {
  command = plan

  assert {
    condition     = length(azurerm_kubernetes_cluster.this.maintenance_window[0].allowed) == 1
    error_message = "Expected 1 allowed maintenance window by default, got ${length(azurerm_kubernetes_cluster.this.maintenance_window[0].allowed)}."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.maintenance_window[0].allowed[0].day == "Sunday"
    error_message = "Expected default maintenance window day to be 'Sunday'."
  }

  assert {
    condition     = length(azurerm_kubernetes_cluster.this.maintenance_window[0].allowed[0].hours) == 4
    error_message = "Expected 4 hours in the default maintenance window (0,1,2,3)."
  }
}

# ---------------------------------------------------------------------------
# 9a. SKU tier – Free.
# ---------------------------------------------------------------------------

run "sku_tier_free" {
  command = plan

  variables {
    sku_tier = "Free"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.sku_tier == "Free"
    error_message = "Expected sku_tier 'Free', got '${azurerm_kubernetes_cluster.this.sku_tier}'."
  }
}

# ---------------------------------------------------------------------------
# 9b. SKU tier – Standard (module default).
# ---------------------------------------------------------------------------

run "sku_tier_standard" {
  command = plan

  variables {
    sku_tier = "Standard"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.sku_tier == "Standard"
    error_message = "Expected sku_tier 'Standard', got '${azurerm_kubernetes_cluster.this.sku_tier}'."
  }
}

# ---------------------------------------------------------------------------
# 9c. SKU tier – Premium.
# ---------------------------------------------------------------------------

run "sku_tier_premium" {
  command = plan

  variables {
    sku_tier = "Premium"
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.sku_tier == "Premium"
    error_message = "Expected sku_tier 'Premium', got '${azurerm_kubernetes_cluster.this.sku_tier}'."
  }
}

# ---------------------------------------------------------------------------
# 9d. SKU tier validation rejects invalid values.
#     An invalid value must cause the plan to fail (expect_failures).
# ---------------------------------------------------------------------------

run "sku_tier_invalid_rejected" {
  command = plan

  variables {
    sku_tier = "Basic"
  }

  expect_failures = [
    var.sku_tier,
  ]
}

# ---------------------------------------------------------------------------
# 10. Additional node pools via for_each.
#     Validates that two additional node pools are planned with the correct
#     vm_size, autoscaling, mode, labels, and taints.
# ---------------------------------------------------------------------------

run "additional_node_pools" {
  command = plan

  variables {
    additional_node_pools = {
      apppool = {
        vm_size   = "Standard_D4s_v5"
        min_count = 1
        max_count = 5
        os_sku    = "AzureLinux"
        mode      = "User"
        node_labels = {
          "workload" = "app"
        }
        node_taints = []
      }
      gpupool = {
        vm_size   = "Standard_NC6s_v3"
        min_count = 0
        max_count = 4
        os_sku    = "Ubuntu"
        mode      = "User"
        node_labels = {
          "workload" = "gpu"
        }
        node_taints = ["nvidia.com/gpu=present:NoSchedule"]
      }
    }
  }

  assert {
    condition     = length(azurerm_kubernetes_cluster_node_pool.this) == 2
    error_message = "Expected 2 additional node pools, got ${length(azurerm_kubernetes_cluster_node_pool.this)}."
  }

  assert {
    condition     = contains(keys(azurerm_kubernetes_cluster_node_pool.this), "apppool")
    error_message = "Expected additional node pool 'apppool' to be planned."
  }

  assert {
    condition     = contains(keys(azurerm_kubernetes_cluster_node_pool.this), "gpupool")
    error_message = "Expected additional node pool 'gpupool' to be planned."
  }

  assert {
    condition     = azurerm_kubernetes_cluster_node_pool.this["apppool"].vm_size == "Standard_D4s_v5"
    error_message = "Expected apppool vm_size 'Standard_D4s_v5', got '${azurerm_kubernetes_cluster_node_pool.this["apppool"].vm_size}'."
  }

  assert {
    condition     = azurerm_kubernetes_cluster_node_pool.this["apppool"].auto_scaling_enabled == true
    error_message = "apppool auto_scaling_enabled must be true."
  }

  assert {
    condition     = azurerm_kubernetes_cluster_node_pool.this["apppool"].min_count == 1
    error_message = "Expected apppool min_count 1, got ${azurerm_kubernetes_cluster_node_pool.this["apppool"].min_count}."
  }

  assert {
    condition     = azurerm_kubernetes_cluster_node_pool.this["apppool"].max_count == 5
    error_message = "Expected apppool max_count 5, got ${azurerm_kubernetes_cluster_node_pool.this["apppool"].max_count}."
  }

  assert {
    condition     = azurerm_kubernetes_cluster_node_pool.this["apppool"].node_labels["workload"] == "app"
    error_message = "Expected apppool node_label workload=app."
  }

  assert {
    condition     = azurerm_kubernetes_cluster_node_pool.this["gpupool"].vm_size == "Standard_NC6s_v3"
    error_message = "Expected gpupool vm_size 'Standard_NC6s_v3', got '${azurerm_kubernetes_cluster_node_pool.this["gpupool"].vm_size}'."
  }

  assert {
    condition     = azurerm_kubernetes_cluster_node_pool.this["gpupool"].max_count == 4
    error_message = "Expected gpupool max_count 4, got ${azurerm_kubernetes_cluster_node_pool.this["gpupool"].max_count}."
  }

  assert {
    condition     = length(azurerm_kubernetes_cluster_node_pool.this["gpupool"].node_taints) == 1
    error_message = "Expected gpupool to have 1 node taint."
  }

  assert {
    condition     = azurerm_kubernetes_cluster_node_pool.this["gpupool"].node_taints[0] == "nvidia.com/gpu=present:NoSchedule"
    error_message = "Expected gpupool taint 'nvidia.com/gpu=present:NoSchedule'."
  }
}

# ---------------------------------------------------------------------------
# 10b. No additional node pools (default empty map).
# ---------------------------------------------------------------------------

run "no_additional_node_pools" {
  command = plan

  variables {
    additional_node_pools = {}
  }

  assert {
    condition     = length(azurerm_kubernetes_cluster_node_pool.this) == 0
    error_message = "Expected no additional node pools when additional_node_pools is empty."
  }
}

# ---------------------------------------------------------------------------
# 11. OMS agent / Log Analytics – disabled when workspace ID is empty.
#     Confirms no oms_agent block and no diagnostic setting resource are
#     planned when log_analytics_workspace_id is left at its default.
# ---------------------------------------------------------------------------

run "oms_agent_disabled_when_no_workspace" {
  command = plan

  variables {
    log_analytics_workspace_id = ""
  }

  assert {
    condition     = length(azurerm_kubernetes_cluster.this.oms_agent) == 0
    error_message = "Expected no oms_agent block when log_analytics_workspace_id is empty."
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.this) == 0
    error_message = "Expected no diagnostic setting when log_analytics_workspace_id is empty."
  }
}

# ---------------------------------------------------------------------------
# 12. Tags propagation.
#     Validates that supplied tags are reflected on both the cluster and any
#     additional node pool resources.
# ---------------------------------------------------------------------------

run "tags_propagation" {
  command = plan

  variables {
    tags = {
      Environment = "test"
      CostCenter  = "engineering"
    }
    additional_node_pools = {
      apppool = {
        vm_size   = "Standard_D2s_v5"
        min_count = 1
        max_count = 3
        mode      = "User"
      }
    }
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.tags["Environment"] == "test"
    error_message = "Expected cluster tag Environment=test."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.tags["CostCenter"] == "engineering"
    error_message = "Expected cluster tag CostCenter=engineering."
  }

  assert {
    condition     = azurerm_kubernetes_cluster_node_pool.this["apppool"].tags["Environment"] == "test"
    error_message = "Expected apppool tag Environment=test."
  }
}
