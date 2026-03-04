# Terraform native tests for the network-security-group module
# Run with: terraform test
# All tests are plan-only (command = plan) — no real Azure resources are created.

# ---------------------------------------------------------------------------
# Shared mock provider — avoids real Azure API calls in every run block
# ---------------------------------------------------------------------------
mock_provider "azurerm" {}

# ---------------------------------------------------------------------------
# Test 1 — Basic NSG creation (name, location, resource group, tags)
# ---------------------------------------------------------------------------
run "basic_nsg_creation" {
  command = plan

  variables {
    name                = "nsg-basic"
    resource_group_name = "rg-test"
    location            = "eastus"
    tags = {
      environment = "test"
      owner       = "platform"
    }
  }

  assert {
    condition     = azurerm_network_security_group.this.name == "nsg-basic"
    error_message = "NSG name must match the input variable."
  }

  assert {
    condition     = azurerm_network_security_group.this.location == "eastus"
    error_message = "NSG location must match the input variable."
  }

  assert {
    condition     = azurerm_network_security_group.this.resource_group_name == "rg-test"
    error_message = "Resource group name must match the input variable."
  }

  assert {
    condition     = azurerm_network_security_group.this.tags["environment"] == "test"
    error_message = "NSG tags must include the provided key/value pairs."
  }

  # No diagnostic setting when log_analytics_workspace_id is not supplied
  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.this) == 0
    error_message = "No diagnostic setting should be created when log_analytics_workspace_id is not provided."
  }
}

# ---------------------------------------------------------------------------
# Test 2 — Custom security rules are applied correctly
# ---------------------------------------------------------------------------
run "custom_security_rules" {
  command = plan

  variables {
    name                = "nsg-custom-rules"
    resource_group_name = "rg-test"
    location            = "eastus"
    security_rules = [
      {
        name                       = "AllowHTTPS"
        priority                   = 100
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "443"
        source_address_prefix      = "Internet"
        destination_address_prefix = "VirtualNetwork"
      },
      {
        name                       = "AllowHTTP"
        priority                   = 110
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "80"
        source_address_prefix      = "Internet"
        destination_address_prefix = "VirtualNetwork"
      }
    ]
  }

  # Two rules supplied — the default deny rule must NOT be injected
  assert {
    condition     = length(azurerm_network_security_group.this.security_rule) == 2
    error_message = "Exactly two security rules should be present when two custom rules are provided."
  }

  assert {
    condition = anytrue([
      for r in azurerm_network_security_group.this.security_rule : r.name == "AllowHTTPS"
    ])
    error_message = "AllowHTTPS rule must be present in the security_rule set."
  }

  assert {
    condition = anytrue([
      for r in azurerm_network_security_group.this.security_rule : r.name == "AllowHTTP"
    ])
    error_message = "AllowHTTP rule must be present in the security_rule set."
  }

  assert {
    condition = alltrue([
      for r in azurerm_network_security_group.this.security_rule :
      r.priority != 4096
    ])
    error_message = "The default deny-all rule at priority 4096 must not be injected when custom rules are provided."
  }
}

# ---------------------------------------------------------------------------
# Test 3 — Default deny-all-inbound rule injected at priority 4096
#           when no security_rules are provided
# ---------------------------------------------------------------------------
run "default_deny_all_inbound_rule" {
  command = plan

  variables {
    name                = "nsg-default-deny"
    resource_group_name = "rg-test"
    location            = "eastus"
    security_rules      = []
  }

  assert {
    condition     = length(azurerm_network_security_group.this.security_rule) == 1
    error_message = "Exactly one security rule (the default deny) should be present when no rules are provided."
  }

  assert {
    condition = anytrue([
      for r in azurerm_network_security_group.this.security_rule : r.name == "DenyAllInbound"
    ])
    error_message = "The default deny rule must be named DenyAllInbound."
  }

  assert {
    condition = anytrue([
      for r in azurerm_network_security_group.this.security_rule : r.priority == 4096
    ])
    error_message = "The default deny rule must be at priority 4096."
  }

  assert {
    condition = anytrue([
      for r in azurerm_network_security_group.this.security_rule : r.direction == "Inbound"
    ])
    error_message = "The default deny rule must be an Inbound rule."
  }

  assert {
    condition = anytrue([
      for r in azurerm_network_security_group.this.security_rule : r.access == "Deny"
    ])
    error_message = "The default deny rule must have access set to Deny."
  }

  assert {
    condition = anytrue([
      for r in azurerm_network_security_group.this.security_rule : r.protocol == "*"
    ])
    error_message = "The default deny rule must match all protocols (*)."
  }

  assert {
    condition = anytrue([
      for r in azurerm_network_security_group.this.security_rule :
      r.source_address_prefix == "*" && r.destination_address_prefix == "*"
    ])
    error_message = "The default deny rule must use wildcard source and destination address prefixes."
  }
}

# ---------------------------------------------------------------------------
# Test 4 — Diagnostic setting created when log_analytics_workspace_id is set
# ---------------------------------------------------------------------------
run "diagnostic_settings_created" {
  command = plan

  variables {
    name                       = "nsg-diag"
    resource_group_name        = "rg-test"
    location                   = "eastus"
    log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/law-test"
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.this) == 1
    error_message = "Exactly one diagnostic setting should be created when a Log Analytics workspace ID is provided."
  }

  assert {
    condition     = one(azurerm_monitor_diagnostic_setting.this).name == "nsg-diag-diag"
    error_message = "Diagnostic setting name must follow the pattern '<nsg-name>-diag'."
  }

  assert {
    condition     = one(azurerm_monitor_diagnostic_setting.this).log_analytics_workspace_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/law-test"
    error_message = "Diagnostic setting must reference the provided Log Analytics workspace ID."
  }
}

# ---------------------------------------------------------------------------
# Test 5 — Diagnostic setting NOT created when log_analytics_workspace_id
#           is the default empty string
# ---------------------------------------------------------------------------
run "diagnostic_settings_not_created" {
  command = plan

  variables {
    name                       = "nsg-no-diag"
    resource_group_name        = "rg-test"
    location                   = "eastus"
    log_analytics_workspace_id = ""
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.this) == 0
    error_message = "No diagnostic setting should be created when log_analytics_workspace_id is an empty string."
  }
}

# ---------------------------------------------------------------------------
# Test 6 — Single custom rule retains correct attributes
# ---------------------------------------------------------------------------
run "single_custom_rule_attributes" {
  command = plan

  variables {
    name                = "nsg-single-rule"
    resource_group_name = "rg-test"
    location            = "westeurope"
    security_rules = [
      {
        name                       = "AllowSSH"
        priority                   = 200
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "22"
        source_address_prefix      = "10.0.0.0/8"
        destination_address_prefix = "*"
      }
    ]
  }

  assert {
    condition = anytrue([
      for r in azurerm_network_security_group.this.security_rule :
      r.name == "AllowSSH" && r.priority == 200 && r.protocol == "Tcp" && r.destination_port_range == "22"
    ])
    error_message = "The AllowSSH rule must have the correct priority, protocol, and destination port."
  }

  assert {
    condition = anytrue([
      for r in azurerm_network_security_group.this.security_rule :
      r.source_address_prefix == "10.0.0.0/8"
    ])
    error_message = "The AllowSSH rule must restrict source to the 10.0.0.0/8 prefix."
  }
}
