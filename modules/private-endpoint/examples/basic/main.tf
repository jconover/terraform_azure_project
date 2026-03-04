terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

resource "azurerm_resource_group" "example" {
  name     = "rg-pe-example"
  location = "eastus2"
}

resource "azurerm_virtual_network" "example" {
  name                = "vnet-pe-example"
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "example" {
  name                 = "snet-pe-example"
  resource_group_name  = azurerm_resource_group.example.name
  virtual_network_name = azurerm_virtual_network.example.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_storage_account" "example" {
  name                     = "stpeexample"
  resource_group_name      = azurerm_resource_group.example.name
  location                 = azurerm_resource_group.example.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

module "private_endpoint" {
  source = "../../"

  name                           = "pe-storage-blob"
  resource_group_name            = azurerm_resource_group.example.name
  location                       = azurerm_resource_group.example.location
  subnet_id                      = azurerm_subnet.example.id
  private_connection_resource_id = azurerm_storage_account.example.id
  subresource_names              = ["blob"]

  tags = {
    Environment = "example"
  }
}

output "private_endpoint_id" {
  description = "The resource ID of the deployed private endpoint."
  value       = module.private_endpoint.id
}

output "private_ip_address" {
  description = "The private IP address assigned to the private endpoint network interface."
  value       = module.private_endpoint.private_ip_address
}
