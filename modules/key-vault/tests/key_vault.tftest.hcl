# Terraform native tests for the key-vault module.
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
# 1. Basic Key Vault creation – minimal required inputs, all defaults accepted.
# ---------------------------------------------------------------------------
run "basic_key_vault_creation" {
  command = plan

  variables {
    name                = "kv-basic-test"
    resource_group_name = "rg-test"
    location            = "eastus"
    tenant_id           = "00000000-0000-0000-0000-000000000000"
  }

  assert {
    condition     = azurerm_key_vault.this.name == "kv-basic-test"
    error_message = "Key Vault name must match the provided variable value."
  }

  assert {
    condition     = azurerm_key_vault.this.resource_group_name == "rg-test"
    error_message = "Resource group name must match the provided variable value."
  }

  assert {
    condition     = azurerm_key_vault.this.location == "eastus"
    error_message = "Location must match the provided variable value."
  }

  assert {
    condition     = azurerm_key_vault.this.tenant_id == "00000000-0000-0000-0000-000000000000"
    error_message = "Tenant ID must match the provided variable value."
  }
}

# ---------------------------------------------------------------------------
# 2. RBAC authorization is enabled by default.
# ---------------------------------------------------------------------------
run "rbac_authorization_enabled_by_default" {
  command = plan

  variables {
    name                = "kv-rbac-default"
    resource_group_name = "rg-test"
    location            = "eastus"
    tenant_id           = "00000000-0000-0000-0000-000000000000"
  }

  assert {
    condition     = azurerm_key_vault.this.enable_rbac_authorization == true
    error_message = "RBAC authorization must be enabled by default."
  }
}

run "rbac_authorization_explicit_disable" {
  command = plan

  variables {
    name                       = "kv-rbac-off"
    resource_group_name        = "rg-test"
    location                   = "eastus"
    tenant_id                  = "00000000-0000-0000-0000-000000000000"
    enable_rbac_authorization  = false
  }

  assert {
    condition     = azurerm_key_vault.this.enable_rbac_authorization == false
    error_message = "RBAC authorization must be disabled when explicitly set to false."
  }
}

# ---------------------------------------------------------------------------
# 3. Purge protection is enabled by default.
# ---------------------------------------------------------------------------
run "purge_protection_enabled_by_default" {
  command = plan

  variables {
    name                = "kv-purge-default"
    resource_group_name = "rg-test"
    location            = "eastus"
    tenant_id           = "00000000-0000-0000-0000-000000000000"
  }

  assert {
    condition     = azurerm_key_vault.this.purge_protection_enabled == true
    error_message = "Purge protection must be enabled by default."
  }
}

# ---------------------------------------------------------------------------
# 4. Soft delete retention configuration – default (90), boundary values.
# ---------------------------------------------------------------------------
run "soft_delete_retention_default_90_days" {
  command = plan

  variables {
    name                = "kv-retention-def"
    resource_group_name = "rg-test"
    location            = "eastus"
    tenant_id           = "00000000-0000-0000-0000-000000000000"
    # soft_delete_retention_days intentionally omitted to exercise default.
  }

  assert {
    condition     = azurerm_key_vault.this.soft_delete_retention_days == 90
    error_message = "Default soft delete retention must be 90 days."
  }
}

run "soft_delete_retention_minimum_boundary" {
  command = plan

  variables {
    name                       = "kv-retention-min"
    resource_group_name        = "rg-test"
    location                   = "eastus"
    tenant_id                  = "00000000-0000-0000-0000-000000000000"
    soft_delete_retention_days = 7
  }

  assert {
    condition     = azurerm_key_vault.this.soft_delete_retention_days == 7
    error_message = "Soft delete retention must accept the minimum boundary value of 7."
  }
}

run "soft_delete_retention_custom_value" {
  command = plan

  variables {
    name                       = "kv-retention-cust"
    resource_group_name        = "rg-test"
    location                   = "eastus"
    tenant_id                  = "00000000-0000-0000-0000-000000000000"
    soft_delete_retention_days = 30
  }

  assert {
    condition     = azurerm_key_vault.this.soft_delete_retention_days == 30
    error_message = "Soft delete retention must reflect a custom value of 30."
  }
}

# ---------------------------------------------------------------------------
# 5. Network ACLs default deny.
# ---------------------------------------------------------------------------
run "network_acls_default_deny" {
  command = plan

  variables {
    name                = "kv-acl-deny"
    resource_group_name = "rg-test"
    location            = "eastus"
    tenant_id           = "00000000-0000-0000-0000-000000000000"
    # network_acls_default_action intentionally omitted to exercise default.
  }

  assert {
    condition     = azurerm_key_vault.this.network_acls[0].default_action == "Deny"
    error_message = "Network ACLs default action must be 'Deny'."
  }

  assert {
    condition     = azurerm_key_vault.this.network_acls[0].bypass == "AzureServices"
    error_message = "Network ACLs bypass must be set to 'AzureServices'."
  }
}

run "network_acls_public_access_disabled_by_default" {
  command = plan

  variables {
    name                = "kv-public-off"
    resource_group_name = "rg-test"
    location            = "eastus"
    tenant_id           = "00000000-0000-0000-0000-000000000000"
  }

  assert {
    condition     = azurerm_key_vault.this.public_network_access_enabled == false
    error_message = "Public network access must be disabled by default."
  }
}

# ---------------------------------------------------------------------------
# 6. Diagnostic settings created when log_analytics_workspace_id is provided.
# ---------------------------------------------------------------------------
run "diagnostic_settings_created_with_workspace_id" {
  command = plan

  variables {
    name                       = "kv-diag-enabled"
    resource_group_name        = "rg-test"
    location                   = "eastus"
    tenant_id                  = "00000000-0000-0000-0000-000000000000"
    log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/law-test"
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.this) == 1
    error_message = "Diagnostic setting must be created when log_analytics_workspace_id is provided."
  }

  assert {
    condition     = azurerm_monitor_diagnostic_setting.this[0].name == "kv-diag-enabled-diag"
    error_message = "Diagnostic setting name must follow the '<vault-name>-diag' convention."
  }

  assert {
    condition     = azurerm_monitor_diagnostic_setting.this[0].log_analytics_workspace_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/law-test"
    error_message = "Diagnostic setting must reference the provided Log Analytics workspace ID."
  }
}

# ---------------------------------------------------------------------------
# 7. Diagnostic settings skipped when log_analytics_workspace_id is empty.
# ---------------------------------------------------------------------------
run "diagnostic_settings_skipped_when_empty" {
  command = plan

  variables {
    name                       = "kv-diag-disabled"
    resource_group_name        = "rg-test"
    location                   = "eastus"
    tenant_id                  = "00000000-0000-0000-0000-000000000000"
    log_analytics_workspace_id = ""
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.this) == 0
    error_message = "Diagnostic setting must not be created when log_analytics_workspace_id is empty."
  }
}

run "diagnostic_settings_skipped_by_default" {
  command = plan

  variables {
    name                = "kv-diag-default"
    resource_group_name = "rg-test"
    location            = "eastus"
    tenant_id           = "00000000-0000-0000-0000-000000000000"
    # log_analytics_workspace_id intentionally omitted to exercise default.
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.this) == 0
    error_message = "Diagnostic setting must not be created when log_analytics_workspace_id defaults to empty."
  }
}

# ---------------------------------------------------------------------------
# 8. SKU validation – standard (default) and premium.
# ---------------------------------------------------------------------------
run "sku_default_is_standard" {
  command = plan

  variables {
    name                = "kv-sku-default"
    resource_group_name = "rg-test"
    location            = "eastus"
    tenant_id           = "00000000-0000-0000-0000-000000000000"
    # sku_name intentionally omitted to exercise default.
  }

  assert {
    condition     = azurerm_key_vault.this.sku_name == "standard"
    error_message = "Default SKU must be 'standard'."
  }
}

run "sku_explicit_premium" {
  command = plan

  variables {
    name                = "kv-sku-premium"
    resource_group_name = "rg-test"
    location            = "eastus"
    tenant_id           = "00000000-0000-0000-0000-000000000000"
    sku_name            = "premium"
  }

  assert {
    condition     = azurerm_key_vault.this.sku_name == "premium"
    error_message = "SKU must reflect the explicitly supplied value of 'premium'."
  }
}

# ---------------------------------------------------------------------------
# 9. Tags applied correctly – empty default and a non-empty tag map.
# ---------------------------------------------------------------------------
run "tags_default_empty" {
  command = plan

  variables {
    name                = "kv-tags-empty"
    resource_group_name = "rg-test"
    location            = "eastus"
    tenant_id           = "00000000-0000-0000-0000-000000000000"
    # tags intentionally omitted.
  }

  assert {
    condition     = azurerm_key_vault.this.tags == {}
    error_message = "Default tags must be an empty map."
  }
}

run "tags_applied_correctly" {
  command = plan

  variables {
    name                = "kv-tags-set"
    resource_group_name = "rg-test"
    location            = "eastus"
    tenant_id           = "00000000-0000-0000-0000-000000000000"
    tags = {
      environment = "test"
      team        = "platform"
    }
  }

  assert {
    condition     = azurerm_key_vault.this.tags["environment"] == "test"
    error_message = "Tag 'environment' must be set to 'test'."
  }

  assert {
    condition     = azurerm_key_vault.this.tags["team"] == "platform"
    error_message = "Tag 'team' must be set to 'platform'."
  }

  assert {
    condition     = length(azurerm_key_vault.this.tags) == 2
    error_message = "Exactly two tags must be present on the Key Vault."
  }
}

# ---------------------------------------------------------------------------
# 10. Output values – verify outputs reference correct resource attributes.
# ---------------------------------------------------------------------------
run "output_id_reference" {
  command = plan

  variables {
    name                = "kv-output-id"
    resource_group_name = "rg-test"
    location            = "eastus"
    tenant_id           = "00000000-0000-0000-0000-000000000000"
  }

  assert {
    condition     = output.id == azurerm_key_vault.this.id
    error_message = "Output 'id' must reference the Key Vault resource's id attribute."
  }
}

run "output_name_matches_input" {
  command = plan

  variables {
    name                = "kv-output-name"
    resource_group_name = "rg-test"
    location            = "eastus"
    tenant_id           = "00000000-0000-0000-0000-000000000000"
  }

  assert {
    condition     = output.name == "kv-output-name"
    error_message = "Output 'name' must match the name variable supplied to the module."
  }
}

run "output_vault_uri_reference" {
  command = plan

  variables {
    name                = "kv-output-uri"
    resource_group_name = "rg-test"
    location            = "eastus"
    tenant_id           = "00000000-0000-0000-0000-000000000000"
  }

  assert {
    condition     = output.vault_uri == azurerm_key_vault.this.vault_uri
    error_message = "Output 'vault_uri' must reference the Key Vault resource's vault_uri attribute."
  }
}

run "output_resource_group_name_passthrough" {
  command = plan

  variables {
    name                = "kv-output-rg"
    resource_group_name = "rg-passthrough-test"
    location            = "eastus"
    tenant_id           = "00000000-0000-0000-0000-000000000000"
  }

  assert {
    condition     = output.resource_group_name == "rg-passthrough-test"
    error_message = "Output 'resource_group_name' must pass through the resource group name correctly."
  }
}
