# Terraform native tests for the subnet module
# Run with: terraform test
# All tests are plan-only (command = plan) — no real Azure resources are created.

# ---------------------------------------------------------------------------
# Shared mock provider — avoids real Azure API calls in every run block
# ---------------------------------------------------------------------------
mock_provider "azurerm" {}

# ---------------------------------------------------------------------------
# Test 1 — Basic subnet creation with an address prefix
# ---------------------------------------------------------------------------
run "basic_subnet_creation" {
  command = plan

  variables {
    name                 = "snet-basic"
    resource_group_name  = "rg-test"
    virtual_network_name = "vnet-test"
    address_prefixes     = ["10.0.1.0/24"]
  }

  assert {
    condition     = azurerm_subnet.this.name == "snet-basic"
    error_message = "Subnet name must match the input variable."
  }

  assert {
    condition     = azurerm_subnet.this.resource_group_name == "rg-test"
    error_message = "Resource group name must match the input variable."
  }

  assert {
    condition     = azurerm_subnet.this.virtual_network_name == "vnet-test"
    error_message = "Virtual network name must match the input variable."
  }

  assert {
    condition     = azurerm_subnet.this.address_prefixes == tolist(["10.0.1.0/24"])
    error_message = "Address prefixes must match the input variable."
  }

  # No NSG association should be planned when network_security_group_id is omitted
  assert {
    condition     = length(azurerm_subnet_network_security_group_association.this) == 0
    error_message = "No NSG association resource should be created when network_security_group_id is not provided."
  }
}

# ---------------------------------------------------------------------------
# Test 2 — Service endpoints configuration
# ---------------------------------------------------------------------------
run "service_endpoints_configuration" {
  command = plan

  variables {
    name                 = "snet-endpoints"
    resource_group_name  = "rg-test"
    virtual_network_name = "vnet-test"
    address_prefixes     = ["10.0.2.0/24"]
    service_endpoints    = ["Microsoft.Storage", "Microsoft.KeyVault"]
  }

  assert {
    condition     = azurerm_subnet.this.service_endpoints == toset(["Microsoft.Storage", "Microsoft.KeyVault"])
    error_message = "Service endpoints must match the provided list."
  }
}

# ---------------------------------------------------------------------------
# Test 3 — Empty service_endpoints collapses to null (no attribute set)
# ---------------------------------------------------------------------------
run "empty_service_endpoints_becomes_null" {
  command = plan

  variables {
    name                 = "snet-no-endpoints"
    resource_group_name  = "rg-test"
    virtual_network_name = "vnet-test"
    address_prefixes     = ["10.0.3.0/24"]
    service_endpoints    = []
  }

  assert {
    condition     = azurerm_subnet.this.service_endpoints == null
    error_message = "An empty service_endpoints list must be converted to null."
  }
}

# ---------------------------------------------------------------------------
# Test 4 — Delegation support
# ---------------------------------------------------------------------------
run "delegation_support" {
  command = plan

  variables {
    name                 = "snet-delegation"
    resource_group_name  = "rg-test"
    virtual_network_name = "vnet-test"
    address_prefixes     = ["10.0.4.0/24"]
    delegation = {
      name = "app-service-delegation"
      service_delegation = {
        name    = "Microsoft.Web/serverFarms"
        actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
      }
    }
  }

  assert {
    condition     = length(azurerm_subnet.this.delegation) == 1
    error_message = "Exactly one delegation block should be present."
  }

  assert {
    condition     = one(azurerm_subnet.this.delegation).name == "app-service-delegation"
    error_message = "Delegation name must match the input."
  }

  assert {
    condition     = one(one(azurerm_subnet.this.delegation).service_delegation).name == "Microsoft.Web/serverFarms"
    error_message = "Service delegation name must match the input."
  }
}

# ---------------------------------------------------------------------------
# Test 5 — No delegation block when delegation is null (default)
# ---------------------------------------------------------------------------
run "no_delegation_when_null" {
  command = plan

  variables {
    name                 = "snet-no-delegation"
    resource_group_name  = "rg-test"
    virtual_network_name = "vnet-test"
    address_prefixes     = ["10.0.5.0/24"]
  }

  assert {
    condition     = length(azurerm_subnet.this.delegation) == 0
    error_message = "No delegation block should be rendered when delegation is null."
  }
}

# ---------------------------------------------------------------------------
# Test 6 — Private endpoint network policies setting
# ---------------------------------------------------------------------------
run "private_endpoint_network_policies_disabled" {
  command = plan

  variables {
    name                              = "snet-pe"
    resource_group_name               = "rg-test"
    virtual_network_name              = "vnet-test"
    address_prefixes                  = ["10.0.6.0/24"]
    private_endpoint_network_policies = "Disabled"
  }

  assert {
    condition     = azurerm_subnet.this.private_endpoint_network_policies == "Disabled"
    error_message = "private_endpoint_network_policies must be set to Disabled."
  }
}

run "private_endpoint_network_policies_default_enabled" {
  command = plan

  variables {
    name                 = "snet-pe-default"
    resource_group_name  = "rg-test"
    virtual_network_name = "vnet-test"
    address_prefixes     = ["10.0.7.0/24"]
  }

  assert {
    condition     = azurerm_subnet.this.private_endpoint_network_policies == "Enabled"
    error_message = "private_endpoint_network_policies must default to Enabled."
  }
}

# ---------------------------------------------------------------------------
# Test 7 — NSG association is created when an NSG ID is provided
# ---------------------------------------------------------------------------
run "nsg_association_created" {
  command = plan

  variables {
    name                      = "snet-nsg"
    resource_group_name       = "rg-test"
    virtual_network_name      = "vnet-test"
    address_prefixes          = ["10.0.8.0/24"]
    network_security_group_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/networkSecurityGroups/nsg-test"
  }

  assert {
    condition     = length(azurerm_subnet_network_security_group_association.this) == 1
    error_message = "Exactly one NSG association resource should be created when a network_security_group_id is provided."
  }

  assert {
    condition     = one(azurerm_subnet_network_security_group_association.this).network_security_group_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/networkSecurityGroups/nsg-test"
    error_message = "NSG association must reference the provided NSG ID."
  }
}

# ---------------------------------------------------------------------------
# Test 8 — No NSG association when network_security_group_id is empty string
# ---------------------------------------------------------------------------
run "nsg_association_not_created_for_empty_id" {
  command = plan

  variables {
    name                      = "snet-no-nsg"
    resource_group_name       = "rg-test"
    virtual_network_name      = "vnet-test"
    address_prefixes          = ["10.0.9.0/24"]
    network_security_group_id = ""
  }

  assert {
    condition     = length(azurerm_subnet_network_security_group_association.this) == 0
    error_message = "No NSG association should be created when network_security_group_id is an empty string."
  }
}
