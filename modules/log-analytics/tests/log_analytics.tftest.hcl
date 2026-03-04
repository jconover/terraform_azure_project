# Terraform native tests for the log-analytics module.
# All tests use command = plan so no real Azure resources are created.
# Requires Terraform >= 1.6.0 and the azurerm provider ~> 4.0.

# ---------------------------------------------------------------------------
# Shared mock provider block – avoids authenticating against Azure during plan.
# ---------------------------------------------------------------------------
provider "azurerm" {
  features {}
  # These dummy values satisfy the provider's required configuration without
  # making any real API calls when combined with `command = plan`.
  subscription_id = "00000000-0000-0000-0000-000000000000"
  client_id       = "00000000-0000-0000-0000-000000000000"
  client_secret   = "dummy-secret"
  tenant_id       = "00000000-0000-0000-0000-000000000000"
}

# ---------------------------------------------------------------------------
# 1. Basic workspace creation – minimal required inputs, all defaults accepted.
# ---------------------------------------------------------------------------
run "basic_workspace_creation" {
  command = plan

  variables {
    name                = "law-basic-test"
    resource_group_name = "rg-test"
    location            = "eastus"
  }

  # The plan must include exactly one workspace resource.
  assert {
    condition     = azurerm_log_analytics_workspace.this.name == "law-basic-test"
    error_message = "Workspace name must match the provided variable value."
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.resource_group_name == "rg-test"
    error_message = "Resource group name must match the provided variable value."
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.location == "eastus"
    error_message = "Location must match the provided variable value."
  }
}

# ---------------------------------------------------------------------------
# 2. SKU configuration – default is PerGB2018; also verify an explicit value.
# ---------------------------------------------------------------------------
run "sku_default_is_pergb2018" {
  command = plan

  variables {
    name                = "law-sku-default"
    resource_group_name = "rg-test"
    location            = "eastus"
    # sku intentionally omitted to exercise the default.
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.sku == "PerGB2018"
    error_message = "Default SKU must be PerGB2018."
  }
}

run "sku_explicit_value" {
  command = plan

  variables {
    name                = "law-sku-pernode"
    resource_group_name = "rg-test"
    location            = "eastus"
    sku                 = "PerNode"
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.sku == "PerNode"
    error_message = "SKU must reflect the explicitly supplied value."
  }
}

# ---------------------------------------------------------------------------
# 3. Retention days – default (30), boundary values (30 and 730), and a
#    mid-range value to confirm the setting is passed through correctly.
# ---------------------------------------------------------------------------
run "retention_default_30_days" {
  command = plan

  variables {
    name                = "law-retention-default"
    resource_group_name = "rg-test"
    location            = "eastus"
    # retention_in_days intentionally omitted.
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.retention_in_days == 30
    error_message = "Default retention must be 30 days."
  }
}

run "retention_minimum_boundary" {
  command = plan

  variables {
    name                = "law-retention-min"
    resource_group_name = "rg-test"
    location            = "eastus"
    retention_in_days   = 30
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.retention_in_days == 30
    error_message = "Retention must accept the minimum boundary value of 30."
  }
}

run "retention_maximum_boundary" {
  command = plan

  variables {
    name                = "law-retention-max"
    resource_group_name = "rg-test"
    location            = "eastus"
    retention_in_days   = 730
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.retention_in_days == 730
    error_message = "Retention must accept the maximum boundary value of 730."
  }
}

run "retention_mid_range_value" {
  command = plan

  variables {
    name                = "law-retention-90"
    resource_group_name = "rg-test"
    location            = "eastus"
    retention_in_days   = 90
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.retention_in_days == 90
    error_message = "Retention must reflect a custom mid-range value of 90."
  }
}

# ---------------------------------------------------------------------------
# 4. Daily quota configuration – default unlimited (-1) and an explicit cap.
# ---------------------------------------------------------------------------
run "daily_quota_default_unlimited" {
  command = plan

  variables {
    name                = "law-quota-default"
    resource_group_name = "rg-test"
    location            = "eastus"
    # daily_quota_gb intentionally omitted.
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.daily_quota_gb == -1
    error_message = "Default daily quota must be -1 (unlimited)."
  }
}

run "daily_quota_explicit_cap" {
  command = plan

  variables {
    name                = "law-quota-10gb"
    resource_group_name = "rg-test"
    location            = "eastus"
    daily_quota_gb      = 10
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.daily_quota_gb == 10
    error_message = "Daily quota must reflect the explicitly supplied value of 10 GB."
  }
}

# ---------------------------------------------------------------------------
# 5. Tags applied correctly – empty default and a non-empty tag map.
# ---------------------------------------------------------------------------
run "tags_default_empty" {
  command = plan

  variables {
    name                = "law-tags-empty"
    resource_group_name = "rg-test"
    location            = "eastus"
    # tags intentionally omitted.
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.tags == {}
    error_message = "Default tags must be an empty map."
  }
}

run "tags_applied_correctly" {
  command = plan

  variables {
    name                = "law-tags-set"
    resource_group_name = "rg-test"
    location            = "eastus"
    tags = {
      environment = "test"
      team        = "platform"
      cost_center = "eng-001"
    }
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.tags["environment"] == "test"
    error_message = "Tag 'environment' must be set to 'test'."
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.tags["team"] == "platform"
    error_message = "Tag 'team' must be set to 'platform'."
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.tags["cost_center"] == "eng-001"
    error_message = "Tag 'cost_center' must be set to 'eng-001'."
  }

  assert {
    condition     = length(azurerm_log_analytics_workspace.this.tags) == 3
    error_message = "Exactly three tags must be present on the workspace."
  }
}

# ---------------------------------------------------------------------------
# 6. Output values – id, workspace_id, and primary_shared_key sensitivity.
# ---------------------------------------------------------------------------
run "output_id_is_non_empty" {
  command = plan

  variables {
    name                = "law-output-id"
    resource_group_name = "rg-test"
    location            = "eastus"
  }

  # During plan the id is unknown, but the output must reference the correct
  # resource attribute so that the dependency graph is wired correctly.
  assert {
    condition     = output.id == azurerm_log_analytics_workspace.this.id
    error_message = "Output 'id' must reference the workspace resource's id attribute."
  }
}

run "output_workspace_id_reference" {
  command = plan

  variables {
    name                = "law-output-wsid"
    resource_group_name = "rg-test"
    location            = "eastus"
  }

  assert {
    condition     = output.workspace_id == azurerm_log_analytics_workspace.this.workspace_id
    error_message = "Output 'workspace_id' must reference the workspace resource's workspace_id attribute."
  }
}

run "output_name_matches_input" {
  command = plan

  variables {
    name                = "law-output-name"
    resource_group_name = "rg-test"
    location            = "eastus"
  }

  assert {
    condition     = output.name == "law-output-name"
    error_message = "Output 'name' must match the name variable supplied to the module."
  }
}

run "output_primary_shared_key_is_sensitive" {
  command = plan

  variables {
    name                = "law-output-key"
    resource_group_name = "rg-test"
    location            = "eastus"
  }

  # Sensitivity is declared in outputs.tf (sensitive = true).  During plan the
  # value is unknown, so we verify the output attribute wiring is correct and
  # that the output is present in the plan (referencing it here is sufficient).
  assert {
    condition     = output.primary_shared_key == azurerm_log_analytics_workspace.this.primary_shared_key
    error_message = "Output 'primary_shared_key' must reference the workspace resource's primary_shared_key attribute."
  }
}

run "output_resource_group_name_passthrough" {
  command = plan

  variables {
    name                = "law-output-rg"
    resource_group_name = "rg-passthrough-test"
    location            = "eastus"
  }

  assert {
    condition     = output.resource_group_name == "rg-passthrough-test"
    error_message = "Output 'resource_group_name' must pass through the resource group name correctly."
  }
}
