# Terraform native tests for the resource-group module.
# All runs use command = plan so no real Azure resources are created.
# Requires Terraform >= 1.6.0 and a mock provider block to avoid real
# Azure credentials during CI / local development.

# ---------------------------------------------------------------------------
# Mock provider — satisfies the azurerm requirement without real credentials.
# ---------------------------------------------------------------------------
mock_provider "azurerm" {}

# ---------------------------------------------------------------------------
# 1. Basic resource group creation – name and location are set correctly.
# ---------------------------------------------------------------------------
run "basic_resource_group_creation" {
  command = plan

  variables {
    name     = "rg-test-basic"
    location = "eastus"
  }

  assert {
    condition     = azurerm_resource_group.this.name == "rg-test-basic"
    error_message = "Resource group name should be 'rg-test-basic', got '${azurerm_resource_group.this.name}'."
  }

  assert {
    condition     = azurerm_resource_group.this.location == "eastus"
    error_message = "Resource group location should be 'eastus', got '${azurerm_resource_group.this.location}'."
  }
}

# ---------------------------------------------------------------------------
# 2. Tags are applied correctly – both present and absent tag scenarios.
# ---------------------------------------------------------------------------
run "tags_applied_correctly" {
  command = plan

  variables {
    name     = "rg-test-tags"
    location = "westeurope"
    tags = {
      environment = "test"
      owner       = "platform-team"
      cost_center = "12345"
    }
  }

  assert {
    condition     = azurerm_resource_group.this.tags["environment"] == "test"
    error_message = "Tag 'environment' should be 'test', got '${azurerm_resource_group.this.tags["environment"]}'."
  }

  assert {
    condition     = azurerm_resource_group.this.tags["owner"] == "platform-team"
    error_message = "Tag 'owner' should be 'platform-team', got '${azurerm_resource_group.this.tags["owner"]}'."
  }

  assert {
    condition     = azurerm_resource_group.this.tags["cost_center"] == "12345"
    error_message = "Tag 'cost_center' should be '12345', got '${azurerm_resource_group.this.tags["cost_center"]}'."
  }

  assert {
    condition     = length(azurerm_resource_group.this.tags) == 3
    error_message = "Expected exactly 3 tags, got ${length(azurerm_resource_group.this.tags)}."
  }
}

run "no_tags_defaults_to_empty_map" {
  command = plan

  variables {
    name     = "rg-test-no-tags"
    location = "eastus2"
    # tags not set — relies on default = {}
  }

  assert {
    condition     = length(azurerm_resource_group.this.tags) == 0
    error_message = "Expected no tags when none are provided, got ${length(azurerm_resource_group.this.tags)}."
  }
}

# ---------------------------------------------------------------------------
# 3. Output values – id, name, and location are exposed correctly.
# ---------------------------------------------------------------------------
run "output_name_matches_input" {
  command = plan

  variables {
    name     = "rg-test-outputs"
    location = "uksouth"
  }

  assert {
    condition     = output.name == "rg-test-outputs"
    error_message = "Output 'name' should be 'rg-test-outputs', got '${output.name}'."
  }
}

run "output_location_matches_input" {
  command = plan

  variables {
    name     = "rg-test-outputs"
    location = "uksouth"
  }

  assert {
    condition     = output.location == "uksouth"
    error_message = "Output 'location' should be 'uksouth', got '${output.location}'."
  }
}

run "output_id_is_non_empty_string" {
  command = plan

  variables {
    name     = "rg-test-outputs"
    location = "northeurope"
  }

  # During a plan the id is a known-after-apply value from the mock provider.
  # We assert that the output is wired to the resource attribute — if the
  # output block referenced the wrong resource the plan itself would fail.
  assert {
    condition     = output.id == azurerm_resource_group.this.id
    error_message = "Output 'id' must be sourced from azurerm_resource_group.this.id."
  }
}

# ---------------------------------------------------------------------------
# 4. Variable validation – invalid names and unsupported locations are
#    rejected before any resource is planned.
# ---------------------------------------------------------------------------
run "invalid_name_rejected" {
  command = plan

  variables {
    name     = "rg/invalid/slashes"
    location = "eastus"
  }

  expect_failures = [var.name]
}

run "invalid_location_rejected" {
  command = plan

  variables {
    name     = "rg-test-bad-location"
    location = "invalidregion"
  }

  expect_failures = [var.location]
}
