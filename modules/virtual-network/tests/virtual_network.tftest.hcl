# Terraform native tests for the virtual-network module.
# All tests use command = plan so no real Azure resources are created.
# Requires Terraform >= 1.6.0 and the azurerm provider ~> 4.0.

provider "azurerm" {
  features {}
  # Skip actual Azure authentication during plan-only tests.
  skip_provider_registration = true
}

# ---------------------------------------------------------------------------
# 1. Basic VNet creation with a single address space
# ---------------------------------------------------------------------------
run "basic_vnet_creation" {
  command = plan

  variables {
    name                = "vnet-basic-test"
    resource_group_name = "rg-test"
    location            = "eastus"
    address_space       = ["10.0.0.0/16"]
  }

  assert {
    condition     = azurerm_virtual_network.this.name == "vnet-basic-test"
    error_message = "Virtual network name does not match the supplied variable."
  }

  assert {
    condition     = azurerm_virtual_network.this.resource_group_name == "rg-test"
    error_message = "Resource group name does not match the supplied variable."
  }

  assert {
    condition     = azurerm_virtual_network.this.location == "eastus"
    error_message = "Location does not match the supplied variable."
  }

  assert {
    condition     = azurerm_virtual_network.this.address_space == tolist(["10.0.0.0/16"])
    error_message = "Address space does not match the supplied variable."
  }

  # No log_analytics_workspace_id supplied, so the diagnostic setting must be absent.
  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.this) == 0
    error_message = "Diagnostic setting should not be created when log_analytics_workspace_id is empty."
  }
}

# ---------------------------------------------------------------------------
# 2. Custom DNS servers configuration
# ---------------------------------------------------------------------------
run "custom_dns_servers" {
  command = plan

  variables {
    name                = "vnet-dns-test"
    resource_group_name = "rg-test"
    location            = "westus2"
    address_space       = ["10.1.0.0/16"]
    dns_servers         = ["10.1.0.4", "10.1.0.5"]
  }

  assert {
    condition     = azurerm_virtual_network.this.dns_servers == tolist(["10.1.0.4", "10.1.0.5"])
    error_message = "DNS servers do not match the supplied variable."
  }

  # Verify the default (no DNS) path is the inverse — dns_servers must not be empty here.
  assert {
    condition     = length(azurerm_virtual_network.this.dns_servers) == 2
    error_message = "Expected exactly two DNS server entries."
  }
}

# ---------------------------------------------------------------------------
# 3. Tags applied correctly
# ---------------------------------------------------------------------------
run "tags_applied" {
  command = plan

  variables {
    name                = "vnet-tags-test"
    resource_group_name = "rg-test"
    location            = "eastus"
    address_space       = ["10.2.0.0/16"]
    tags = {
      environment = "production"
      team        = "platform"
      cost_center = "12345"
    }
  }

  assert {
    condition     = azurerm_virtual_network.this.tags["environment"] == "production"
    error_message = "Tag 'environment' does not have the expected value 'production'."
  }

  assert {
    condition     = azurerm_virtual_network.this.tags["team"] == "platform"
    error_message = "Tag 'team' does not have the expected value 'platform'."
  }

  assert {
    condition     = azurerm_virtual_network.this.tags["cost_center"] == "12345"
    error_message = "Tag 'cost_center' does not have the expected value '12345'."
  }

  assert {
    condition     = length(azurerm_virtual_network.this.tags) == 3
    error_message = "Expected exactly 3 tags on the virtual network."
  }
}

# ---------------------------------------------------------------------------
# 4a. Diagnostic settings created when log_analytics_workspace_id is provided
# ---------------------------------------------------------------------------
run "diagnostic_settings_enabled" {
  command = plan

  variables {
    name                       = "vnet-diag-test"
    resource_group_name        = "rg-test"
    location                   = "eastus"
    address_space              = ["10.3.0.0/16"]
    log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/law-test"
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.this) == 1
    error_message = "Expected exactly one diagnostic setting when log_analytics_workspace_id is provided."
  }

  assert {
    condition     = azurerm_monitor_diagnostic_setting.this[0].name == "vnet-diag-test-diag"
    error_message = "Diagnostic setting name should follow the pattern '<vnet-name>-diag'."
  }

  assert {
    condition     = azurerm_monitor_diagnostic_setting.this[0].log_analytics_workspace_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/law-test"
    error_message = "Diagnostic setting log_analytics_workspace_id does not match the supplied variable."
  }
}

# ---------------------------------------------------------------------------
# 4b. Diagnostic settings omitted when log_analytics_workspace_id is empty
# ---------------------------------------------------------------------------
run "diagnostic_settings_disabled" {
  command = plan

  variables {
    name                       = "vnet-nodiag-test"
    resource_group_name        = "rg-test"
    location                   = "eastus"
    address_space              = ["10.4.0.0/16"]
    log_analytics_workspace_id = ""
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.this) == 0
    error_message = "Diagnostic setting should not be created when log_analytics_workspace_id is an empty string."
  }
}

# ---------------------------------------------------------------------------
# 5. Multiple address spaces
# ---------------------------------------------------------------------------
run "multiple_address_spaces" {
  command = plan

  variables {
    name                = "vnet-multi-cidr-test"
    resource_group_name = "rg-test"
    location            = "northeurope"
    address_space       = ["10.5.0.0/16", "172.16.0.0/12", "192.168.0.0/24"]
  }

  assert {
    condition     = length(azurerm_virtual_network.this.address_space) == 3
    error_message = "Expected exactly three CIDR blocks in the address space."
  }

  assert {
    condition     = contains(azurerm_virtual_network.this.address_space, "10.5.0.0/16")
    error_message = "Address space should contain '10.5.0.0/16'."
  }

  assert {
    condition     = contains(azurerm_virtual_network.this.address_space, "172.16.0.0/12")
    error_message = "Address space should contain '172.16.0.0/12'."
  }

  assert {
    condition     = contains(azurerm_virtual_network.this.address_space, "192.168.0.0/24")
    error_message = "Address space should contain '192.168.0.0/24'."
  }
}
