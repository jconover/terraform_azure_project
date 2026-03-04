# Terraform native tests for the storage-account module.
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
  name                = "teststorage01"
  resource_group_name = "test-rg"
  location            = "eastus2"
}

# ---------------------------------------------------------------------------
# 1. Basic storage account creation with required variables only.
#    Verifies the storage account resource is planned with the supplied name,
#    location, resource group, and default settings.
# ---------------------------------------------------------------------------

run "basic_storage_account_creation" {
  command = plan

  variables {
    name                = "basicsa01"
    resource_group_name = "basic-rg"
    location            = "eastus2"
  }

  assert {
    condition     = azurerm_storage_account.this.name == "basicsa01"
    error_message = "Expected storage account name to be 'basicsa01', got '${azurerm_storage_account.this.name}'."
  }

  assert {
    condition     = azurerm_storage_account.this.location == "eastus2"
    error_message = "Expected location to be 'eastus2', got '${azurerm_storage_account.this.location}'."
  }

  assert {
    condition     = azurerm_storage_account.this.resource_group_name == "basic-rg"
    error_message = "Expected resource_group_name to be 'basic-rg', got '${azurerm_storage_account.this.resource_group_name}'."
  }

  assert {
    condition     = azurerm_storage_account.this.account_tier == "Standard"
    error_message = "Expected default account_tier to be 'Standard', got '${azurerm_storage_account.this.account_tier}'."
  }

  assert {
    condition     = azurerm_storage_account.this.account_replication_type == "LRS"
    error_message = "Expected default account_replication_type to be 'LRS', got '${azurerm_storage_account.this.account_replication_type}'."
  }

  assert {
    condition     = azurerm_storage_account.this.account_kind == "StorageV2"
    error_message = "Expected default account_kind to be 'StorageV2', got '${azurerm_storage_account.this.account_kind}'."
  }
}

# ---------------------------------------------------------------------------
# 2. HTTPS-only enforcement.
#    Confirms https_traffic_only_enabled defaults to true and cannot be
#    overridden to false without explicit intent.
# ---------------------------------------------------------------------------

run "https_only_enforcement_default" {
  command = plan

  assert {
    condition     = azurerm_storage_account.this.https_traffic_only_enabled == true
    error_message = "Expected https_traffic_only_enabled to default to true."
  }
}

run "https_only_enforcement_explicit" {
  command = plan

  variables {
    https_traffic_only_enabled = true
  }

  assert {
    condition     = azurerm_storage_account.this.https_traffic_only_enabled == true
    error_message = "Expected https_traffic_only_enabled to be true when explicitly set."
  }
}

# ---------------------------------------------------------------------------
# 3. TLS 1.2 minimum version.
#    Validates that min_tls_version defaults to TLS1_2 for security
#    compliance.
# ---------------------------------------------------------------------------

run "tls_minimum_version_default" {
  command = plan

  assert {
    condition     = azurerm_storage_account.this.min_tls_version == "TLS1_2"
    error_message = "Expected min_tls_version to default to 'TLS1_2', got '${azurerm_storage_account.this.min_tls_version}'."
  }
}

run "tls_minimum_version_custom" {
  command = plan

  variables {
    min_tls_version = "TLS1_2"
  }

  assert {
    condition     = azurerm_storage_account.this.min_tls_version == "TLS1_2"
    error_message = "Expected min_tls_version to be 'TLS1_2', got '${azurerm_storage_account.this.min_tls_version}'."
  }
}

# ---------------------------------------------------------------------------
# 4. Shared access key disabled.
#    Confirms shared_access_key_enabled defaults to false (RBAC preferred).
# ---------------------------------------------------------------------------

run "shared_access_key_disabled_default" {
  command = plan

  assert {
    condition     = azurerm_storage_account.this.shared_access_key_enabled == false
    error_message = "Expected shared_access_key_enabled to default to false (RBAC preferred)."
  }
}

run "shared_access_key_disabled_explicit" {
  command = plan

  variables {
    shared_access_key_enabled = false
  }

  assert {
    condition     = azurerm_storage_account.this.shared_access_key_enabled == false
    error_message = "Expected shared_access_key_enabled to be false when explicitly set."
  }
}

# ---------------------------------------------------------------------------
# 5. Network rules default deny.
#    Validates that the network_rules block defaults to Deny, preventing
#    unrestricted access to the storage account.
# ---------------------------------------------------------------------------

run "network_rules_default_deny" {
  command = plan

  assert {
    condition     = azurerm_storage_account.this.network_rules[0].default_action == "Deny"
    error_message = "Expected network_rules default_action to be 'Deny', got '${azurerm_storage_account.this.network_rules[0].default_action}'."
  }

  assert {
    condition     = length(azurerm_storage_account.this.network_rules[0].ip_rules) == 0
    error_message = "Expected no IP rules by default."
  }

  assert {
    condition     = length(azurerm_storage_account.this.network_rules[0].virtual_network_subnet_ids) == 0
    error_message = "Expected no virtual network subnet IDs by default."
  }
}

run "network_rules_custom_ip_rules" {
  command = plan

  variables {
    network_rules_default_action = "Deny"
    network_rules_ip_rules       = ["203.0.113.0/24", "198.51.100.0/24"]
    network_rules_bypass         = ["AzureServices", "Logging"]
  }

  assert {
    condition     = azurerm_storage_account.this.network_rules[0].default_action == "Deny"
    error_message = "Expected network_rules default_action to be 'Deny'."
  }

  assert {
    condition     = length(azurerm_storage_account.this.network_rules[0].ip_rules) == 2
    error_message = "Expected 2 IP rules, got ${length(azurerm_storage_account.this.network_rules[0].ip_rules)}."
  }
}

run "network_rules_bypass_default" {
  command = plan

  assert {
    condition     = contains(azurerm_storage_account.this.network_rules[0].bypass, "AzureServices")
    error_message = "Expected network_rules bypass to include 'AzureServices' by default."
  }
}

# ---------------------------------------------------------------------------
# 6. Blob soft delete configuration.
#    Verifies that blob soft delete retention defaults to 30 days and can
#    be customized.
# ---------------------------------------------------------------------------

run "blob_soft_delete_default" {
  command = plan

  assert {
    condition     = azurerm_storage_account.this.blob_properties[0].delete_retention_policy[0].days == 30
    error_message = "Expected blob soft delete retention to default to 30 days, got ${azurerm_storage_account.this.blob_properties[0].delete_retention_policy[0].days}."
  }
}

run "blob_soft_delete_custom" {
  command = plan

  variables {
    blob_soft_delete_retention_days = 90
  }

  assert {
    condition     = azurerm_storage_account.this.blob_properties[0].delete_retention_policy[0].days == 90
    error_message = "Expected blob soft delete retention to be 90 days, got ${azurerm_storage_account.this.blob_properties[0].delete_retention_policy[0].days}."
  }
}

run "blob_soft_delete_minimum" {
  command = plan

  variables {
    blob_soft_delete_retention_days = 1
  }

  assert {
    condition     = azurerm_storage_account.this.blob_properties[0].delete_retention_policy[0].days == 1
    error_message = "Expected blob soft delete retention to be 1 day, got ${azurerm_storage_account.this.blob_properties[0].delete_retention_policy[0].days}."
  }
}

# ---------------------------------------------------------------------------
# 7. Container soft delete configuration.
#    Verifies that container soft delete retention defaults to 30 days and
#    can be customized.
# ---------------------------------------------------------------------------

run "container_soft_delete_default" {
  command = plan

  assert {
    condition     = azurerm_storage_account.this.blob_properties[0].container_delete_retention_policy[0].days == 30
    error_message = "Expected container soft delete retention to default to 30 days, got ${azurerm_storage_account.this.blob_properties[0].container_delete_retention_policy[0].days}."
  }
}

run "container_soft_delete_custom" {
  command = plan

  variables {
    container_soft_delete_retention_days = 60
  }

  assert {
    condition     = azurerm_storage_account.this.blob_properties[0].container_delete_retention_policy[0].days == 60
    error_message = "Expected container soft delete retention to be 60 days, got ${azurerm_storage_account.this.blob_properties[0].container_delete_retention_policy[0].days}."
  }
}

# ---------------------------------------------------------------------------
# 8. Versioning enabled.
#    Confirms that blob versioning defaults to true for data protection.
# ---------------------------------------------------------------------------

run "versioning_enabled_default" {
  command = plan

  assert {
    condition     = azurerm_storage_account.this.blob_properties[0].versioning_enabled == true
    error_message = "Expected versioning_enabled to default to true."
  }
}

run "versioning_disabled_explicit" {
  command = plan

  variables {
    versioning_enabled = false
  }

  assert {
    condition     = azurerm_storage_account.this.blob_properties[0].versioning_enabled == false
    error_message = "Expected versioning_enabled to be false when explicitly disabled."
  }
}

# ---------------------------------------------------------------------------
# 9. Lifecycle rules configuration.
#    Validates that lifecycle management rules are planned correctly when
#    provided, and that no management policy is created when rules are empty.
# ---------------------------------------------------------------------------

run "lifecycle_rules_configured" {
  command = plan

  variables {
    lifecycle_rules = [
      {
        name                       = "move-to-cool"
        enabled                    = true
        prefix_match               = ["logs/"]
        tier_to_cool_after_days    = 30
        tier_to_archive_after_days = null
        delete_after_days          = null
      },
      {
        name                       = "archive-old-data"
        enabled                    = true
        prefix_match               = ["archive/"]
        tier_to_cool_after_days    = null
        tier_to_archive_after_days = 90
        delete_after_days          = 365
      }
    ]
  }

  assert {
    condition     = length(azurerm_storage_management_policy.this) == 1
    error_message = "Expected 1 storage management policy when lifecycle rules are provided."
  }
}

run "lifecycle_rules_empty_no_policy" {
  command = plan

  variables {
    lifecycle_rules = []
  }

  assert {
    condition     = length(azurerm_storage_management_policy.this) == 0
    error_message = "Expected no storage management policy when lifecycle_rules is empty."
  }
}

run "lifecycle_rules_single_rule" {
  command = plan

  variables {
    lifecycle_rules = [
      {
        name                       = "delete-old-blobs"
        enabled                    = true
        prefix_match               = []
        tier_to_cool_after_days    = null
        tier_to_archive_after_days = null
        delete_after_days          = 180
      }
    ]
  }

  assert {
    condition     = length(azurerm_storage_management_policy.this) == 1
    error_message = "Expected 1 storage management policy for a single lifecycle rule."
  }
}

# ---------------------------------------------------------------------------
# 10. Diagnostic settings conditional creation.
#     Confirms that the diagnostic setting is only created when a Log
#     Analytics workspace ID is provided.
# ---------------------------------------------------------------------------

run "diagnostic_settings_enabled" {
  command = plan

  variables {
    log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.OperationalInsights/workspaces/test-law"
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.this) == 1
    error_message = "Expected 1 diagnostic setting when log_analytics_workspace_id is provided."
  }

  assert {
    condition     = azurerm_monitor_diagnostic_setting.this[0].name == "teststorage01-diag"
    error_message = "Expected diagnostic setting name to be 'teststorage01-diag', got '${azurerm_monitor_diagnostic_setting.this[0].name}'."
  }

  assert {
    condition     = azurerm_monitor_diagnostic_setting.this[0].log_analytics_workspace_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.OperationalInsights/workspaces/test-law"
    error_message = "Expected diagnostic setting to reference the supplied Log Analytics workspace ID."
  }
}

run "diagnostic_settings_disabled" {
  command = plan

  variables {
    log_analytics_workspace_id = ""
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.this) == 0
    error_message = "Expected no diagnostic setting when log_analytics_workspace_id is empty."
  }
}

# ---------------------------------------------------------------------------
# 11. Tags propagation.
#     Validates that supplied tags are reflected on the storage account.
# ---------------------------------------------------------------------------

run "tags_propagation" {
  command = plan

  variables {
    tags = {
      Environment = "test"
      CostCenter  = "engineering"
    }
  }

  assert {
    condition     = azurerm_storage_account.this.tags["Environment"] == "test"
    error_message = "Expected storage account tag Environment=test."
  }

  assert {
    condition     = azurerm_storage_account.this.tags["CostCenter"] == "engineering"
    error_message = "Expected storage account tag CostCenter=engineering."
  }
}

# ---------------------------------------------------------------------------
# 12. Storage account name validation rejects invalid values.
#     An invalid name (contains hyphens) must cause the plan to fail.
# ---------------------------------------------------------------------------

run "name_validation_rejects_hyphens" {
  command = plan

  variables {
    name = "invalid-name-01"
  }

  expect_failures = [
    var.name,
  ]
}

run "name_validation_rejects_too_short" {
  command = plan

  variables {
    name = "ab"
  }

  expect_failures = [
    var.name,
  ]
}

# ---------------------------------------------------------------------------
# 13. Containers creation via for_each.
#     Validates that storage containers are planned correctly.
# ---------------------------------------------------------------------------

run "containers_creation" {
  command = plan

  variables {
    containers = {
      "data" = {
        access_type = "private"
      }
      "logs" = {
        access_type = "private"
      }
    }
  }

  assert {
    condition     = length(azurerm_storage_container.this) == 2
    error_message = "Expected 2 storage containers, got ${length(azurerm_storage_container.this)}."
  }

  assert {
    condition     = contains(keys(azurerm_storage_container.this), "data")
    error_message = "Expected storage container 'data' to be planned."
  }

  assert {
    condition     = contains(keys(azurerm_storage_container.this), "logs")
    error_message = "Expected storage container 'logs' to be planned."
  }
}

run "containers_empty_default" {
  command = plan

  variables {
    containers = {}
  }

  assert {
    condition     = length(azurerm_storage_container.this) == 0
    error_message = "Expected no storage containers when containers map is empty."
  }
}
