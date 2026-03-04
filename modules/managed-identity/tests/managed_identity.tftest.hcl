# Terraform native tests for the managed-identity module
# Requires Terraform 1.6+
# All tests run in plan-only mode (command = plan)

# ---------------------------------------------------------------------------
# Shared provider mock – no real Azure credentials required for plan-only runs
# ---------------------------------------------------------------------------
mock_provider "azurerm" {}

# ---------------------------------------------------------------------------
# Test 1: User-assigned identity is created when type = "UserAssigned"
# ---------------------------------------------------------------------------
run "user_assigned_identity_created" {
  command = plan

  variables {
    name                = "id-test-userassigned"
    resource_group_name = "rg-test"
    location            = "eastus"
    type                = "UserAssigned"
    tags                = {}
  }

  # The resource block count should be 1
  assert {
    condition     = length(azurerm_user_assigned_identity.this) == 1
    error_message = "Expected exactly one user-assigned identity resource to be planned."
  }

  assert {
    condition     = azurerm_user_assigned_identity.this[0].name == "id-test-userassigned"
    error_message = "Identity name does not match the provided variable."
  }

  assert {
    condition     = azurerm_user_assigned_identity.this[0].resource_group_name == "rg-test"
    error_message = "Resource group name does not match the provided variable."
  }

  assert {
    condition     = azurerm_user_assigned_identity.this[0].location == "eastus"
    error_message = "Location does not match the provided variable."
  }
}

# ---------------------------------------------------------------------------
# Test 2: No identity resource is created when type = "SystemAssigned"
# ---------------------------------------------------------------------------
run "system_assigned_skips_resource" {
  command = plan

  variables {
    name                = "id-test-sysassigned"
    resource_group_name = "rg-test"
    location            = "eastus"
    type                = "SystemAssigned"
    tags                = {}
  }

  assert {
    condition     = length(azurerm_user_assigned_identity.this) == 0
    error_message = "No user-assigned identity resource should be planned when type is SystemAssigned."
  }
}

# ---------------------------------------------------------------------------
# Test 3: Tags are applied correctly to the identity resource
# ---------------------------------------------------------------------------
run "tags_applied_correctly" {
  command = plan

  variables {
    name                = "id-test-tags"
    resource_group_name = "rg-test"
    location            = "westus2"
    type                = "UserAssigned"
    tags = {
      environment = "test"
      owner       = "platform-team"
      cost_center = "12345"
    }
  }

  assert {
    condition     = azurerm_user_assigned_identity.this[0].tags["environment"] == "test"
    error_message = "Tag 'environment' was not applied correctly."
  }

  assert {
    condition     = azurerm_user_assigned_identity.this[0].tags["owner"] == "platform-team"
    error_message = "Tag 'owner' was not applied correctly."
  }

  assert {
    condition     = azurerm_user_assigned_identity.this[0].tags["cost_center"] == "12345"
    error_message = "Tag 'cost_center' was not applied correctly."
  }

  assert {
    condition     = length(azurerm_user_assigned_identity.this[0].tags) == 3
    error_message = "Unexpected number of tags on the identity resource."
  }
}

# ---------------------------------------------------------------------------
# Test 4: Output values are correctly wired to the resource attributes
# ---------------------------------------------------------------------------
run "output_values_wired_correctly" {
  command = plan

  variables {
    name                = "id-test-outputs"
    resource_group_name = "rg-outputs"
    location            = "eastus"
    type                = "UserAssigned"
    tags                = {}
  }

  # For plan-only with a mock provider the computed attributes (principal_id,
  # client_id) will be known-after-apply placeholders, so we verify that the
  # outputs are defined and that the non-computed output (name) is correct.
  assert {
    condition     = output.name == "id-test-outputs"
    error_message = "Output 'name' does not match the input variable."
  }

  # id, principal_id, and client_id are computed by Azure; confirm they are
  # non-null (mock provider supplies placeholder values, not null).
  assert {
    condition     = output.id != null
    error_message = "Output 'id' should not be null for a UserAssigned identity."
  }

  assert {
    condition     = output.principal_id != null
    error_message = "Output 'principal_id' should not be null for a UserAssigned identity."
  }

  assert {
    condition     = output.client_id != null
    error_message = "Output 'client_id' should not be null for a UserAssigned identity."
  }
}

# ---------------------------------------------------------------------------
# Test 5: Outputs are null when type = "SystemAssigned" (no resource created)
# ---------------------------------------------------------------------------
run "outputs_null_for_system_assigned" {
  command = plan

  variables {
    name                = "id-test-null-outputs"
    resource_group_name = "rg-test"
    location            = "eastus"
    type                = "SystemAssigned"
    tags                = {}
  }

  assert {
    condition     = output.id == null
    error_message = "Output 'id' should be null when type is SystemAssigned."
  }

  assert {
    condition     = output.principal_id == null
    error_message = "Output 'principal_id' should be null when type is SystemAssigned."
  }

  assert {
    condition     = output.client_id == null
    error_message = "Output 'client_id' should be null when type is SystemAssigned."
  }
}

# ---------------------------------------------------------------------------
# Test 6: Variable validation rejects invalid identity types
# ---------------------------------------------------------------------------
run "invalid_identity_type_rejected" {
  command = plan

  variables {
    name                = "id-test-invalid"
    resource_group_name = "rg-test"
    location            = "eastus"
    type                = "InvalidType"
    tags                = {}
  }

  expect_failures = [
    var.type,
  ]
}
