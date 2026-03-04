# Terraform native tests for the private-endpoint module.
# All tests use command = plan so no real Azure resources are created.

provider "azurerm" {
  features {}
  skip_provider_registration = true
}

# ---------------------------------------------------------------------------
# Shared mock values used across multiple test runs.
# ---------------------------------------------------------------------------

variables {
  resource_group_name            = "rg-test"
  location                       = "eastus2"
  subnet_id                      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test"
  private_connection_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Storage/storageAccounts/sttest"
}

# ---------------------------------------------------------------------------
# 1. Basic private endpoint creation
# ---------------------------------------------------------------------------

run "basic_private_endpoint" {
  command = plan

  variables {
    name                           = "pe-basic-test"
    resource_group_name            = var.resource_group_name
    location                       = var.location
    subnet_id                      = var.subnet_id
    private_connection_resource_id = var.private_connection_resource_id
    subresource_names              = ["blob"]
  }

  assert {
    condition     = azurerm_private_endpoint.this.name == "pe-basic-test"
    error_message = "Private endpoint name should be 'pe-basic-test', got: ${azurerm_private_endpoint.this.name}"
  }

  assert {
    condition     = azurerm_private_endpoint.this.resource_group_name == "rg-test"
    error_message = "Resource group name should be 'rg-test', got: ${azurerm_private_endpoint.this.resource_group_name}"
  }

  assert {
    condition     = azurerm_private_endpoint.this.location == "eastus2"
    error_message = "Location should be 'eastus2', got: ${azurerm_private_endpoint.this.location}"
  }

  assert {
    condition     = azurerm_private_endpoint.this.subnet_id == var.subnet_id
    error_message = "Subnet ID does not match the supplied value."
  }

  assert {
    condition     = azurerm_private_endpoint.this.private_service_connection[0].name == "pe-basic-test-psc"
    error_message = "Private service connection name should follow the '<name>-psc' convention."
  }

  assert {
    condition     = azurerm_private_endpoint.this.private_service_connection[0].private_connection_resource_id == var.private_connection_resource_id
    error_message = "Private connection resource ID does not match the supplied value."
  }

  assert {
    condition     = azurerm_private_endpoint.this.private_service_connection[0].is_manual_connection == false
    error_message = "is_manual_connection should default to false."
  }
}

# ---------------------------------------------------------------------------
# 2. Private DNS zone group configuration
# ---------------------------------------------------------------------------

run "private_dns_zone_group_configured" {
  command = plan

  variables {
    name                           = "pe-dns-test"
    resource_group_name            = var.resource_group_name
    location                       = var.location
    subnet_id                      = var.subnet_id
    private_connection_resource_id = var.private_connection_resource_id
    subresource_names              = ["blob"]
    private_dns_zone_ids = [
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
    ]
  }

  assert {
    condition     = length(azurerm_private_endpoint.this.private_dns_zone_group) == 1
    error_message = "Expected exactly one private_dns_zone_group block when DNS zone IDs are provided."
  }

  assert {
    condition     = azurerm_private_endpoint.this.private_dns_zone_group[0].name == "pe-dns-test-dns-zone-group"
    error_message = "DNS zone group name should follow the '<name>-dns-zone-group' convention."
  }

  assert {
    condition     = length(azurerm_private_endpoint.this.private_dns_zone_group[0].private_dns_zone_ids) == 1
    error_message = "DNS zone group should contain exactly one zone ID."
  }

  assert {
    condition     = azurerm_private_endpoint.this.private_dns_zone_group[0].private_dns_zone_ids[0] == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
    error_message = "DNS zone group should contain the supplied zone ID."
  }
}

# ---------------------------------------------------------------------------
# 3. DNS zone group skipped when no DNS zone IDs provided
# ---------------------------------------------------------------------------

run "no_dns_zone_group_when_ids_empty" {
  command = plan

  variables {
    name                           = "pe-nodns-test"
    resource_group_name            = var.resource_group_name
    location                       = var.location
    subnet_id                      = var.subnet_id
    private_connection_resource_id = var.private_connection_resource_id
    subresource_names              = ["blob"]
    private_dns_zone_ids           = []
  }

  assert {
    condition     = length(azurerm_private_endpoint.this.private_dns_zone_group) == 0
    error_message = "No private_dns_zone_group block should be created when private_dns_zone_ids is empty."
  }
}

# ---------------------------------------------------------------------------
# 4. Tags applied correctly
# ---------------------------------------------------------------------------

run "tags_applied" {
  command = plan

  variables {
    name                           = "pe-tags-test"
    resource_group_name            = var.resource_group_name
    location                       = var.location
    subnet_id                      = var.subnet_id
    private_connection_resource_id = var.private_connection_resource_id
    subresource_names              = ["blob"]
    tags = {
      Environment = "test"
      Owner       = "platform-team"
      CostCenter  = "12345"
    }
  }

  assert {
    condition     = azurerm_private_endpoint.this.tags["Environment"] == "test"
    error_message = "Tag 'Environment' should be 'test'."
  }

  assert {
    condition     = azurerm_private_endpoint.this.tags["Owner"] == "platform-team"
    error_message = "Tag 'Owner' should be 'platform-team'."
  }

  assert {
    condition     = azurerm_private_endpoint.this.tags["CostCenter"] == "12345"
    error_message = "Tag 'CostCenter' should be '12345'."
  }

  assert {
    condition     = length(azurerm_private_endpoint.this.tags) == 3
    error_message = "Exactly 3 tags should be applied; got ${length(azurerm_private_endpoint.this.tags)}."
  }
}

# ---------------------------------------------------------------------------
# 4b. Empty tags produce no tag map entries (default behaviour)
# ---------------------------------------------------------------------------

run "empty_tags_default" {
  command = plan

  variables {
    name                           = "pe-notags-test"
    resource_group_name            = var.resource_group_name
    location                       = var.location
    subnet_id                      = var.subnet_id
    private_connection_resource_id = var.private_connection_resource_id
    subresource_names              = ["blob"]
  }

  assert {
    condition     = length(azurerm_private_endpoint.this.tags) == 0
    error_message = "No tags should be applied when the tags variable uses its default empty map."
  }
}

# ---------------------------------------------------------------------------
# 5. Subresource names configuration
# ---------------------------------------------------------------------------

run "subresource_names_blob" {
  command = plan

  variables {
    name                           = "pe-blob-test"
    resource_group_name            = var.resource_group_name
    location                       = var.location
    subnet_id                      = var.subnet_id
    private_connection_resource_id = var.private_connection_resource_id
    subresource_names              = ["blob"]
  }

  assert {
    condition     = azurerm_private_endpoint.this.private_service_connection[0].subresource_names == tolist(["blob"])
    error_message = "subresource_names should be ['blob']."
  }
}

run "subresource_names_vault" {
  command = plan

  variables {
    name                           = "pe-vault-test"
    resource_group_name            = var.resource_group_name
    location                       = var.location
    subnet_id                      = var.subnet_id
    private_connection_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.KeyVault/vaults/kv-test"
    subresource_names              = ["vault"]
  }

  assert {
    condition     = azurerm_private_endpoint.this.private_service_connection[0].subresource_names == tolist(["vault"])
    error_message = "subresource_names should be ['vault'] for a Key Vault private endpoint."
  }
}

run "subresource_names_multiple" {
  command = plan

  variables {
    name                           = "pe-multi-test"
    resource_group_name            = var.resource_group_name
    location                       = var.location
    subnet_id                      = var.subnet_id
    private_connection_resource_id = var.private_connection_resource_id
    subresource_names              = ["blob", "file"]
  }

  assert {
    condition     = length(azurerm_private_endpoint.this.private_service_connection[0].subresource_names) == 2
    error_message = "Two subresource names should be passed through to the private service connection."
  }

  assert {
    condition     = contains(azurerm_private_endpoint.this.private_service_connection[0].subresource_names, "blob")
    error_message = "subresource_names should contain 'blob'."
  }

  assert {
    condition     = contains(azurerm_private_endpoint.this.private_service_connection[0].subresource_names, "file")
    error_message = "subresource_names should contain 'file'."
  }
}

# ---------------------------------------------------------------------------
# 5b. Manual connection flag passes through correctly
# ---------------------------------------------------------------------------

run "manual_connection_flag" {
  command = plan

  variables {
    name                           = "pe-manual-test"
    resource_group_name            = var.resource_group_name
    location                       = var.location
    subnet_id                      = var.subnet_id
    private_connection_resource_id = var.private_connection_resource_id
    subresource_names              = ["blob"]
    is_manual_connection           = true
  }

  assert {
    condition     = azurerm_private_endpoint.this.private_service_connection[0].is_manual_connection == true
    error_message = "is_manual_connection should be true when explicitly set."
  }
}
