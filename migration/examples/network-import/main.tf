# ---------------------------------------------------------------------------
# Worked Example: Import existing Bicep-deployed Networking Resources
# ---------------------------------------------------------------------------
# This configuration imports a VNet, two Subnets, and an NSG that were
# originally deployed via Bicep.  Each resource needs its own import block.
# Remove all import blocks after the first successful `terraform apply`.
# ---------------------------------------------------------------------------

locals {
  subscription_id     = var.subscription_id
  resource_group_name = var.resource_group_name
  vnet_name           = var.vnet_name
  location            = var.location

  # Base path for resource IDs
  rg_id   = "/subscriptions/${local.subscription_id}/resourceGroups/${local.resource_group_name}"
  vnet_id = "${local.rg_id}/providers/Microsoft.Network/virtualNetworks/${local.vnet_name}"
}

# --- Import Blocks (Terraform 1.5+) ---------------------------------------
# Remove these blocks after the first successful `terraform apply`.

import {
  to = module.migrated_vnet.azurerm_virtual_network.this
  id = local.vnet_id
}

import {
  to = module.migrated_subnet_app.azurerm_subnet.this
  id = "${local.vnet_id}/subnets/${var.subnet_app_name}"
}

import {
  to = module.migrated_subnet_app.azurerm_subnet_network_security_group_association.this[0]
  id = "${local.vnet_id}/subnets/${var.subnet_app_name}"
}

import {
  to = module.migrated_subnet_data.azurerm_subnet.this
  id = "${local.vnet_id}/subnets/${var.subnet_data_name}"
}

import {
  to = module.migrated_nsg.azurerm_network_security_group.this
  id = "${local.rg_id}/providers/Microsoft.Network/networkSecurityGroups/${var.nsg_name}"
}

# --- NSG (import first — no dependencies) ---------------------------------
module "migrated_nsg" {
  source = "../../../modules/network-security-group"

  name                = var.nsg_name
  resource_group_name = local.resource_group_name
  location            = local.location

  security_rules = [
    {
      name                       = "AllowHTTPS"
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "443"
      source_address_prefix      = "*"
      destination_address_prefix = "VirtualNetwork"
    },
    {
      name                       = "DenyAllInbound"
      priority                   = 4096
      direction                  = "Inbound"
      access                     = "Deny"
      protocol                   = "*"
      source_port_range          = "*"
      destination_port_range     = "*"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    },
  ]

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

# --- Virtual Network -------------------------------------------------------
module "migrated_vnet" {
  source = "../../../modules/virtual-network"

  name                = local.vnet_name
  resource_group_name = local.resource_group_name
  location            = local.location
  address_space       = var.address_space

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

# --- Subnet: Application Tier (with NSG association) -----------------------
module "migrated_subnet_app" {
  source = "../../../modules/subnet"

  name                 = var.subnet_app_name
  resource_group_name  = local.resource_group_name
  virtual_network_name = module.migrated_vnet.name
  address_prefixes     = ["10.0.1.0/24"]

  network_security_group_id = module.migrated_nsg.id
}

# --- Subnet: Data Tier (with service endpoint) ----------------------------
module "migrated_subnet_data" {
  source = "../../../modules/subnet"

  name                 = var.subnet_data_name
  resource_group_name  = local.resource_group_name
  virtual_network_name = module.migrated_vnet.name
  address_prefixes     = ["10.0.2.0/24"]

  service_endpoints = ["Microsoft.Storage"]
}
