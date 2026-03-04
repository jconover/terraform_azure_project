# Terraform native tests for the rbac-assignment module
# Requires Terraform 1.6+
# All tests run in plan-only mode (command = plan)

# ---------------------------------------------------------------------------
# Shared provider mock – no real Azure credentials required for plan-only runs
# ---------------------------------------------------------------------------
mock_provider "azurerm" {}

# ---------------------------------------------------------------------------
# Test 1: Basic role assignment with a built-in role
# ---------------------------------------------------------------------------
run "basic_builtin_role_assignment" {
  command = plan

  variables {
    role_assignments = {
      app_reader = {
        scope                = "/subscriptions/00000000-0000-0000-0000-000000000001"
        role_definition_name = "Reader"
        principal_id         = "aaaaaaaa-0000-0000-0000-000000000001"
        principal_type       = "ServicePrincipal"
        description          = "Read-only access for the application identity"
      }
    }
    custom_role_definitions = {}
  }

  assert {
    condition     = length(azurerm_role_assignment.this) == 1
    error_message = "Expected exactly one role assignment to be planned."
  }

  assert {
    condition     = azurerm_role_assignment.this["app_reader"].role_definition_name == "Reader"
    error_message = "Role definition name does not match 'Reader'."
  }

  assert {
    condition     = azurerm_role_assignment.this["app_reader"].scope == "/subscriptions/00000000-0000-0000-0000-000000000001"
    error_message = "Scope does not match the provided subscription scope."
  }

  assert {
    condition     = azurerm_role_assignment.this["app_reader"].principal_id == "aaaaaaaa-0000-0000-0000-000000000001"
    error_message = "Principal ID does not match the provided value."
  }

  assert {
    condition     = azurerm_role_assignment.this["app_reader"].principal_type == "ServicePrincipal"
    error_message = "Principal type should default to 'ServicePrincipal'."
  }
}

# ---------------------------------------------------------------------------
# Test 2: Multiple role assignments planned in a single module call
# ---------------------------------------------------------------------------
run "multiple_role_assignments" {
  command = plan

  variables {
    role_assignments = {
      identity_contributor = {
        scope                = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-app"
        role_definition_name = "Contributor"
        principal_id         = "aaaaaaaa-0000-0000-0000-000000000002"
        principal_type       = "ServicePrincipal"
        description          = "Contributor on app resource group"
      }
      identity_reader = {
        scope                = "/subscriptions/00000000-0000-0000-0000-000000000001"
        role_definition_name = "Reader"
        principal_id         = "aaaaaaaa-0000-0000-0000-000000000003"
        principal_type       = "ServicePrincipal"
        description          = "Reader at subscription level"
      }
    }
    custom_role_definitions = {}
  }

  assert {
    condition     = length(azurerm_role_assignment.this) == 2
    error_message = "Expected two role assignments to be planned."
  }

  assert {
    condition     = contains(keys(azurerm_role_assignment.this), "identity_contributor")
    error_message = "Expected 'identity_contributor' key in the planned role assignments."
  }

  assert {
    condition     = contains(keys(azurerm_role_assignment.this), "identity_reader")
    error_message = "Expected 'identity_reader' key in the planned role assignments."
  }
}

# ---------------------------------------------------------------------------
# Test 3: Scope set to a resource group (narrower than subscription)
# ---------------------------------------------------------------------------
run "resource_group_scope_assignment" {
  command = plan

  variables {
    role_assignments = {
      rg_scoped = {
        scope                = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-prod"
        role_definition_name = "Storage Blob Data Reader"
        principal_id         = "aaaaaaaa-0000-0000-0000-000000000004"
        principal_type       = "ServicePrincipal"
        description          = "Storage read access scoped to rg-prod"
      }
    }
    custom_role_definitions = {}
  }

  assert {
    condition     = azurerm_role_assignment.this["rg_scoped"].scope == "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-prod"
    error_message = "Scope should be the resource group path."
  }

  assert {
    condition     = azurerm_role_assignment.this["rg_scoped"].role_definition_name == "Storage Blob Data Reader"
    error_message = "Role definition name should be 'Storage Blob Data Reader'."
  }
}

# ---------------------------------------------------------------------------
# Test 4: Custom role definition is planned correctly
# ---------------------------------------------------------------------------
run "custom_role_definition_created" {
  command = plan

  variables {
    role_assignments = {}
    custom_role_definitions = {
      limited_vm_operator = {
        name        = "Limited VM Operator"
        scope       = "/subscriptions/00000000-0000-0000-0000-000000000001"
        description = "Start and stop VMs, read diagnostics"
        permissions = {
          actions = [
            "Microsoft.Compute/virtualMachines/start/action",
            "Microsoft.Compute/virtualMachines/deallocate/action",
            "Microsoft.Compute/virtualMachines/read",
          ]
          not_actions      = []
          data_actions     = []
          not_data_actions = []
        }
        assignable_scopes = [
          "/subscriptions/00000000-0000-0000-0000-000000000001",
        ]
      }
    }
  }

  assert {
    condition     = length(azurerm_role_definition.this) == 1
    error_message = "Expected exactly one custom role definition to be planned."
  }

  assert {
    condition     = azurerm_role_definition.this["limited_vm_operator"].name == "Limited VM Operator"
    error_message = "Custom role definition name does not match."
  }

  assert {
    condition     = azurerm_role_definition.this["limited_vm_operator"].scope == "/subscriptions/00000000-0000-0000-0000-000000000001"
    error_message = "Custom role definition scope does not match."
  }

  assert {
    condition     = length(azurerm_role_definition.this["limited_vm_operator"].permissions[0].actions) == 3
    error_message = "Expected three actions in the custom role definition permissions."
  }

  assert {
    condition = contains(
      azurerm_role_definition.this["limited_vm_operator"].permissions[0].actions,
      "Microsoft.Compute/virtualMachines/read"
    )
    error_message = "Expected 'Microsoft.Compute/virtualMachines/read' in custom role actions."
  }
}

# ---------------------------------------------------------------------------
# Test 5: Custom role definition with data actions
# ---------------------------------------------------------------------------
run "custom_role_with_data_actions" {
  command = plan

  variables {
    role_assignments = {}
    custom_role_definitions = {
      blob_reader_custom = {
        name        = "Custom Blob Reader"
        scope       = "/subscriptions/00000000-0000-0000-0000-000000000001"
        description = "Custom role to read blob data"
        permissions = {
          actions = [
            "Microsoft.Storage/storageAccounts/read",
          ]
          not_actions = []
          data_actions = [
            "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read",
          ]
          not_data_actions = []
        }
        assignable_scopes = [
          "/subscriptions/00000000-0000-0000-0000-000000000001",
        ]
      }
    }
  }

  assert {
    condition     = length(azurerm_role_definition.this["blob_reader_custom"].permissions[0].data_actions) == 1
    error_message = "Expected one data action in the custom role definition."
  }

  assert {
    condition = contains(
      azurerm_role_definition.this["blob_reader_custom"].permissions[0].data_actions,
      "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read"
    )
    error_message = "Expected blob read data action in the custom role."
  }
}

# ---------------------------------------------------------------------------
# Test 6: Owner role assignment without EXCEPTION-APPROVED triggers precondition
# ---------------------------------------------------------------------------
run "owner_role_without_exception_fails" {
  command = plan

  variables {
    role_assignments = {
      bad_owner = {
        scope                = "/subscriptions/00000000-0000-0000-0000-000000000001"
        role_definition_name = "Owner"
        principal_id         = "aaaaaaaa-0000-0000-0000-000000000005"
        principal_type       = "ServicePrincipal"
        description          = "Trying to assign Owner without approval"
      }
    }
    custom_role_definitions = {}
  }

  # The lifecycle precondition on azurerm_role_assignment.this must fire
  expect_failures = [
    azurerm_role_assignment.this["bad_owner"],
  ]
}

# ---------------------------------------------------------------------------
# Test 7: Owner role WITH EXCEPTION-APPROVED in description is allowed
# ---------------------------------------------------------------------------
run "owner_role_with_exception_approved" {
  command = plan

  variables {
    role_assignments = {
      approved_owner = {
        scope                = "/subscriptions/00000000-0000-0000-0000-000000000001"
        role_definition_name = "Owner"
        principal_id         = "aaaaaaaa-0000-0000-0000-000000000006"
        principal_type       = "ServicePrincipal"
        description          = "EXCEPTION-APPROVED: break-glass owner for incident response"
      }
    }
    custom_role_definitions = {}
  }

  assert {
    condition     = length(azurerm_role_assignment.this) == 1
    error_message = "Owner assignment with EXCEPTION-APPROVED in description should be planned successfully."
  }

  assert {
    condition     = azurerm_role_assignment.this["approved_owner"].role_definition_name == "Owner"
    error_message = "Role definition name should be 'Owner' for the approved assignment."
  }
}

# ---------------------------------------------------------------------------
# Test 8: Non-Owner elevated role (Contributor) does not trigger precondition
# ---------------------------------------------------------------------------
run "contributor_role_no_precondition" {
  command = plan

  variables {
    role_assignments = {
      contributor_assign = {
        scope                = "/subscriptions/00000000-0000-0000-0000-000000000001"
        role_definition_name = "Contributor"
        principal_id         = "aaaaaaaa-0000-0000-0000-000000000007"
        principal_type       = "ServicePrincipal"
        description          = "Standard contributor without any exception token"
      }
    }
    custom_role_definitions = {}
  }

  assert {
    condition     = length(azurerm_role_assignment.this) == 1
    error_message = "Contributor role should be planned without triggering the Owner precondition."
  }

  assert {
    condition     = azurerm_role_assignment.this["contributor_assign"].role_definition_name == "Contributor"
    error_message = "Role definition name should be 'Contributor'."
  }
}

# ---------------------------------------------------------------------------
# Test 9: Output maps are keyed correctly
# ---------------------------------------------------------------------------
run "output_maps_keyed_correctly" {
  command = plan

  variables {
    role_assignments = {
      key_a = {
        scope                = "/subscriptions/00000000-0000-0000-0000-000000000001"
        role_definition_name = "Reader"
        principal_id         = "aaaaaaaa-0000-0000-0000-000000000008"
        principal_type       = "ServicePrincipal"
        description          = "Reader for output key test"
      }
    }
    custom_role_definitions = {
      custom_key_a = {
        name        = "Output Key Test Role"
        scope       = "/subscriptions/00000000-0000-0000-0000-000000000001"
        description = "Role used to verify output map keys"
        permissions = {
          actions          = ["Microsoft.Resources/subscriptions/resourceGroups/read"]
          not_actions      = []
          data_actions     = []
          not_data_actions = []
        }
        assignable_scopes = ["/subscriptions/00000000-0000-0000-0000-000000000001"]
      }
    }
  }

  assert {
    condition     = contains(keys(output.role_assignment_ids), "key_a")
    error_message = "Output 'role_assignment_ids' should contain the key 'key_a'."
  }

  assert {
    condition     = contains(keys(output.custom_role_definition_ids), "custom_key_a")
    error_message = "Output 'custom_role_definition_ids' should contain the key 'custom_key_a'."
  }
}

# ---------------------------------------------------------------------------
# Test 10: Empty inputs produce empty output maps
# ---------------------------------------------------------------------------
run "empty_inputs_produce_empty_outputs" {
  command = plan

  variables {
    role_assignments        = {}
    custom_role_definitions = {}
  }

  assert {
    condition     = length(output.role_assignment_ids) == 0
    error_message = "Output 'role_assignment_ids' should be empty when no assignments are provided."
  }

  assert {
    condition     = length(output.custom_role_definition_ids) == 0
    error_message = "Output 'custom_role_definition_ids' should be empty when no custom roles are provided."
  }
}
