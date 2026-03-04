# Terraform native tests for the fabric-capacity module.
# All runs use command = plan to avoid live Azure API calls.

# ---------------------------------------------------------------------------
# Shared mock provider – no real Azure credentials required for plan-only runs.
# ---------------------------------------------------------------------------
mock_provider "azurerm" {}

# ---------------------------------------------------------------------------
# Test 1: Basic capacity creation
# Verifies that a Fabric capacity resource is planned with the correct name,
# resource group, location, and that the SKU tier is always "Fabric".
# ---------------------------------------------------------------------------
run "basic_capacity_creation" {
  command = plan

  variables {
    name                = "my-fabric-cap"
    resource_group_name = "rg-fabric-test"
    location            = "East US"
    sku                 = "F2"
    admin_members       = ["admin@example.com"]
    tags                = {}
  }

  assert {
    condition     = azurerm_fabric_capacity.this.name == "my-fabric-cap"
    error_message = "Fabric capacity name must match var.name."
  }

  assert {
    condition     = azurerm_fabric_capacity.this.resource_group_name == "rg-fabric-test"
    error_message = "resource_group_name must match var.resource_group_name."
  }

  assert {
    condition     = azurerm_fabric_capacity.this.location == "East US"
    error_message = "location must match var.location."
  }

  assert {
    condition     = azurerm_fabric_capacity.this.sku[0].name == "F2"
    error_message = "SKU name must match var.sku."
  }

  assert {
    condition     = azurerm_fabric_capacity.this.sku[0].tier == "Fabric"
    error_message = "SKU tier must always be 'Fabric'."
  }
}

# ---------------------------------------------------------------------------
# Test 2: SKU validation – minimum valid SKU (F2)
# Verifies that F2, the smallest allowed SKU, is accepted and planned without
# error.
# ---------------------------------------------------------------------------
run "sku_minimum_f2" {
  command = plan

  variables {
    name                = "cap-sku-f2"
    resource_group_name = "rg-fabric-test"
    location            = "West Europe"
    sku                 = "F2"
    admin_members       = ["admin@example.com"]
  }

  assert {
    condition     = azurerm_fabric_capacity.this.sku[0].name == "F2"
    error_message = "F2 is the minimum valid SKU and must be accepted."
  }
}

# ---------------------------------------------------------------------------
# Test 3: SKU validation – mid-range SKU (F64)
# Verifies that a mid-range SKU (F64) is accepted and set correctly.
# ---------------------------------------------------------------------------
run "sku_midrange_f64" {
  command = plan

  variables {
    name                = "cap-sku-f64"
    resource_group_name = "rg-fabric-test"
    location            = "West Europe"
    sku                 = "F64"
    admin_members       = ["admin@example.com"]
  }

  assert {
    condition     = azurerm_fabric_capacity.this.sku[0].name == "F64"
    error_message = "F64 must be accepted as a valid mid-range SKU."
  }
}

# ---------------------------------------------------------------------------
# Test 4: SKU validation – maximum valid SKU (F2048)
# Verifies that F2048, the largest allowed SKU, is accepted and planned without
# error.
# ---------------------------------------------------------------------------
run "sku_maximum_f2048" {
  command = plan

  variables {
    name                = "cap-sku-f2048"
    resource_group_name = "rg-fabric-test"
    location            = "West Europe"
    sku                 = "F2048"
    admin_members       = ["admin@example.com"]
  }

  assert {
    condition     = azurerm_fabric_capacity.this.sku[0].name == "F2048"
    error_message = "F2048 is the maximum valid SKU and must be accepted."
  }
}

# ---------------------------------------------------------------------------
# Test 5: Admin members – single administrator
# Verifies that a single admin UPN is correctly propagated to the
# administration_members attribute of the planned resource.
# ---------------------------------------------------------------------------
run "admin_members_single" {
  command = plan

  variables {
    name                = "cap-admin-single"
    resource_group_name = "rg-fabric-test"
    location            = "East US"
    sku                 = "F8"
    admin_members       = ["alice@example.com"]
  }

  assert {
    condition     = length(azurerm_fabric_capacity.this.administration_members) == 1
    error_message = "administration_members must contain exactly one entry when one admin is supplied."
  }

  assert {
    condition     = contains(azurerm_fabric_capacity.this.administration_members, "alice@example.com")
    error_message = "administration_members must include the supplied admin UPN."
  }
}

# ---------------------------------------------------------------------------
# Test 6: Admin members – multiple administrators
# Verifies that multiple admin UPNs are all propagated to the planned resource.
# ---------------------------------------------------------------------------
run "admin_members_multiple" {
  command = plan

  variables {
    name                = "cap-admin-multi"
    resource_group_name = "rg-fabric-test"
    location            = "East US"
    sku                 = "F16"
    admin_members       = ["alice@example.com", "bob@example.com", "carol@example.com"]
  }

  assert {
    condition     = length(azurerm_fabric_capacity.this.administration_members) == 3
    error_message = "administration_members must contain all three supplied admin UPNs."
  }

  assert {
    condition     = contains(azurerm_fabric_capacity.this.administration_members, "alice@example.com")
    error_message = "administration_members must include alice@example.com."
  }

  assert {
    condition     = contains(azurerm_fabric_capacity.this.administration_members, "bob@example.com")
    error_message = "administration_members must include bob@example.com."
  }

  assert {
    condition     = contains(azurerm_fabric_capacity.this.administration_members, "carol@example.com")
    error_message = "administration_members must include carol@example.com."
  }
}

# ---------------------------------------------------------------------------
# Test 7: Tags applied correctly
# Verifies that a map of tags is correctly propagated to the planned resource.
# ---------------------------------------------------------------------------
run "tags_applied_correctly" {
  command = plan

  variables {
    name                = "cap-with-tags"
    resource_group_name = "rg-fabric-test"
    location            = "East US"
    sku                 = "F32"
    admin_members       = ["admin@example.com"]
    tags = {
      environment = "production"
      owner       = "data-platform-team"
      cost-center = "CC-1234"
    }
  }

  assert {
    condition     = azurerm_fabric_capacity.this.tags["environment"] == "production"
    error_message = "Tag 'environment' must equal 'production'."
  }

  assert {
    condition     = azurerm_fabric_capacity.this.tags["owner"] == "data-platform-team"
    error_message = "Tag 'owner' must equal 'data-platform-team'."
  }

  assert {
    condition     = azurerm_fabric_capacity.this.tags["cost-center"] == "CC-1234"
    error_message = "Tag 'cost-center' must equal 'CC-1234'."
  }

  assert {
    condition     = length(azurerm_fabric_capacity.this.tags) == 3
    error_message = "Exactly three tags must be applied to the resource."
  }
}

# ---------------------------------------------------------------------------
# Test 8: Empty tags default (no tags supplied)
# Verifies that when no tags are provided the tags attribute defaults to an
# empty map and no tags block is applied.
# ---------------------------------------------------------------------------
run "tags_default_empty" {
  command = plan

  variables {
    name                = "cap-no-tags"
    resource_group_name = "rg-fabric-test"
    location            = "East US"
    sku                 = "F4"
    admin_members       = ["admin@example.com"]
    # tags intentionally omitted – should default to {}
  }

  assert {
    condition     = length(azurerm_fabric_capacity.this.tags) == 0
    error_message = "tags must default to an empty map when not supplied."
  }
}

# ---------------------------------------------------------------------------
# Test 9: Output values match planned resource attributes
# Verifies that all module outputs reference the correct resource attributes
# so consumers receive consistent values.
# ---------------------------------------------------------------------------
run "outputs_match_resource_attributes" {
  command = plan

  variables {
    name                = "cap-outputs"
    resource_group_name = "rg-output-test"
    location            = "North Europe"
    sku                 = "F128"
    admin_members       = ["ops@example.com"]
    tags = {
      env = "staging"
    }
  }

  assert {
    condition     = output.name == azurerm_fabric_capacity.this.name
    error_message = "output.name must equal the resource name attribute."
  }

  assert {
    condition     = output.sku == azurerm_fabric_capacity.this.sku[0].name
    error_message = "output.sku must equal the resource SKU name attribute."
  }

  assert {
    condition     = output.resource_group_name == azurerm_fabric_capacity.this.resource_group_name
    error_message = "output.resource_group_name must equal the resource resource_group_name attribute."
  }

  assert {
    condition     = output.admin_members == azurerm_fabric_capacity.this.administration_members
    error_message = "output.admin_members must equal the resource administration_members attribute."
  }
}
