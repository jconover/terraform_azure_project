# Terraform native tests for the azure-policy module.
# All runs use command = plan to avoid live Azure API calls.

# ---------------------------------------------------------------------------
# Shared mock provider – no real Azure credentials required for plan-only runs.
# ---------------------------------------------------------------------------
mock_provider "azurerm" {}

# ---------------------------------------------------------------------------
# Test 1: Basic policy definition creation
# Verifies that a single custom policy definition is planned with the correct
# name, display_name, description, and mode attributes.
# ---------------------------------------------------------------------------
run "basic_policy_definition_creation" {
  command = plan

  variables {
    scope = "/providers/Microsoft.Management/managementGroups/test-mg"

    policy_definitions = {
      "deny-public-ip" = {
        display_name = "Deny Public IP Creation"
        description  = "Prevents the creation of public IP addresses."
        mode         = "All"
        policy_rule  = jsonencode({
          if = {
            field  = "type"
            equals = "Microsoft.Network/publicIPAddresses"
          }
          then = {
            effect = "deny"
          }
        })
      }
    }

    policy_assignments = {}
  }

  assert {
    condition     = azurerm_policy_definition.this["deny-public-ip"].name == "deny-public-ip"
    error_message = "Policy definition name must match the map key."
  }

  assert {
    condition     = azurerm_policy_definition.this["deny-public-ip"].display_name == "Deny Public IP Creation"
    error_message = "Policy definition display_name must match the supplied value."
  }

  assert {
    condition     = azurerm_policy_definition.this["deny-public-ip"].description == "Prevents the creation of public IP addresses."
    error_message = "Policy definition description must match the supplied value."
  }

  assert {
    condition     = azurerm_policy_definition.this["deny-public-ip"].mode == "All"
    error_message = "Policy definition mode must default to 'All'."
  }

  assert {
    condition     = azurerm_policy_definition.this["deny-public-ip"].policy_type == "Custom"
    error_message = "Policy type must always be 'Custom'."
  }

  assert {
    condition     = azurerm_policy_definition.this["deny-public-ip"].management_group_id == "/providers/Microsoft.Management/managementGroups/test-mg"
    error_message = "management_group_id must be set to the var.scope value."
  }
}

# ---------------------------------------------------------------------------
# Test 2: Policy assignment at subscription scope
# Verifies that a subscription-scoped assignment is planned with the correct
# subscription_id, display_name, description, and policy_definition_id.
# ---------------------------------------------------------------------------
run "policy_assignment_subscription_scope" {
  command = plan

  variables {
    scope = "/providers/Microsoft.Management/managementGroups/test-mg"

    policy_definitions = {}

    policy_assignments = {
      "assign-deny-public-ip" = {
        policy_definition_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyDefinitions/deny-public-ip"
        display_name         = "Deny Public IP Assignment"
        description          = "Enforces the deny-public-ip policy at subscription scope."
        scope                = "/subscriptions/00000000-0000-0000-0000-000000000000"
        enforce              = true
      }
    }
  }

  assert {
    condition     = azurerm_subscription_policy_assignment.this["assign-deny-public-ip"].name == "assign-deny-public-ip"
    error_message = "Policy assignment name must match the map key."
  }

  assert {
    condition     = azurerm_subscription_policy_assignment.this["assign-deny-public-ip"].subscription_id == "/subscriptions/00000000-0000-0000-0000-000000000000"
    error_message = "subscription_id must equal the scope value from the assignment map."
  }

  assert {
    condition     = azurerm_subscription_policy_assignment.this["assign-deny-public-ip"].display_name == "Deny Public IP Assignment"
    error_message = "Policy assignment display_name must match the supplied value."
  }

  assert {
    condition     = azurerm_subscription_policy_assignment.this["assign-deny-public-ip"].description == "Enforces the deny-public-ip policy at subscription scope."
    error_message = "Policy assignment description must match the supplied value."
  }

  assert {
    condition     = azurerm_subscription_policy_assignment.this["assign-deny-public-ip"].policy_definition_id == "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyDefinitions/deny-public-ip"
    error_message = "policy_definition_id must match the supplied value."
  }
}

# ---------------------------------------------------------------------------
# Test 3: Enforcement mode – enforce = true
# Verifies that setting enforce = true on an assignment is reflected in the
# planned resource.
# ---------------------------------------------------------------------------
run "enforcement_mode_enabled" {
  command = plan

  variables {
    scope = "/providers/Microsoft.Management/managementGroups/test-mg"

    policy_definitions = {}

    policy_assignments = {
      "enforced-assignment" = {
        policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/00000000-0000-0000-0000-000000000001"
        display_name         = "Enforced Policy Assignment"
        scope                = "/subscriptions/00000000-0000-0000-0000-000000000000"
        enforce              = true
      }
    }
  }

  assert {
    condition     = azurerm_subscription_policy_assignment.this["enforced-assignment"].enforce == true
    error_message = "enforce must be true when set to true in the assignment map."
  }
}

# ---------------------------------------------------------------------------
# Test 4: Enforcement mode – enforce = false (audit / disabled)
# Verifies that setting enforce = false on an assignment is reflected in the
# planned resource, enabling an audit-only posture.
# ---------------------------------------------------------------------------
run "enforcement_mode_disabled" {
  command = plan

  variables {
    scope = "/providers/Microsoft.Management/managementGroups/test-mg"

    policy_definitions = {}

    policy_assignments = {
      "audit-only-assignment" = {
        policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/00000000-0000-0000-0000-000000000001"
        display_name         = "Audit Only Policy Assignment"
        scope                = "/subscriptions/00000000-0000-0000-0000-000000000000"
        enforce              = false
      }
    }
  }

  assert {
    condition     = azurerm_subscription_policy_assignment.this["audit-only-assignment"].enforce == false
    error_message = "enforce must be false when set to false in the assignment map (audit mode)."
  }
}

# ---------------------------------------------------------------------------
# Test 5: Policy metadata and description
# Verifies that optional metadata JSON and a description are correctly passed
# through to the planned policy definition resource.
# ---------------------------------------------------------------------------
run "policy_metadata_and_description" {
  command = plan

  variables {
    scope = "/providers/Microsoft.Management/managementGroups/test-mg"

    policy_definitions = {
      "require-tags" = {
        display_name = "Require Resource Tags"
        description  = "Requires that all resources have the specified tags applied."
        mode         = "Indexed"
        policy_rule  = jsonencode({
          if = {
            field  = "tags"
            exists = "false"
          }
          then = {
            effect = "audit"
          }
        })
        metadata = jsonencode({
          category = "Tags"
          version  = "1.0.0"
        })
      }
    }

    policy_assignments = {}
  }

  assert {
    condition     = azurerm_policy_definition.this["require-tags"].description == "Requires that all resources have the specified tags applied."
    error_message = "description must match the supplied value."
  }

  assert {
    condition     = azurerm_policy_definition.this["require-tags"].mode == "Indexed"
    error_message = "mode must be 'Indexed' when explicitly set."
  }

  assert {
    condition     = azurerm_policy_definition.this["require-tags"].metadata != null
    error_message = "metadata must be set when a non-empty metadata string is provided."
  }
}

# ---------------------------------------------------------------------------
# Test 6: Default mode when mode is omitted
# Verifies that the mode defaults to "All" when not explicitly specified in
# the policy definition map entry.
# ---------------------------------------------------------------------------
run "policy_definition_default_mode" {
  command = plan

  variables {
    scope = "/providers/Microsoft.Management/managementGroups/test-mg"

    policy_definitions = {
      "no-mode-specified" = {
        display_name = "Policy Without Explicit Mode"
        policy_rule  = jsonencode({
          if = {
            field  = "type"
            equals = "Microsoft.Compute/virtualMachines"
          }
          then = {
            effect = "audit"
          }
        })
        # mode is intentionally omitted – should default to "All"
      }
    }

    policy_assignments = {}
  }

  assert {
    condition     = azurerm_policy_definition.this["no-mode-specified"].mode == "All"
    error_message = "mode must default to 'All' when not explicitly supplied."
  }
}

# ---------------------------------------------------------------------------
# Test 7: Null metadata when metadata is omitted (empty string default)
# Verifies that when no metadata string is provided the planned resource has
# metadata set to null rather than an empty string.
# ---------------------------------------------------------------------------
run "policy_definition_null_metadata_when_omitted" {
  command = plan

  variables {
    scope = "/providers/Microsoft.Management/managementGroups/test-mg"

    policy_definitions = {
      "no-metadata" = {
        display_name = "Policy Without Metadata"
        policy_rule  = jsonencode({
          if = {
            field  = "type"
            equals = "Microsoft.Storage/storageAccounts"
          }
          then = {
            effect = "audit"
          }
        })
        # metadata omitted – defaults to "" which main.tf converts to null
      }
    }

    policy_assignments = {}
  }

  assert {
    condition     = azurerm_policy_definition.this["no-metadata"].metadata == null
    error_message = "metadata must be null in the plan when no metadata string is provided."
  }
}
