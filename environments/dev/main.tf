locals {
  # tflint-ignore: terraform_unused_declarations
  common_tags = merge(
    {
      environment = var.environment
      project     = var.project
      managed_by  = "terraform"
      owner       = var.owner
      cost_center = var.cost_center
    },
    var.tags
  )
}

module "naming" {
  source = "../../modules/naming"

  project     = var.project
  environment = var.environment
  location    = var.location
  unique_seed = var.subscription_id
}

data "azurerm_client_config" "current" {}

# Phase 1: Foundation resources

module "foundation_rg" {
  source = "../../modules/resource-group"

  name     = module.naming.resource_group
  location = var.location
  tags     = local.common_tags
}

module "foundation_law" {
  source = "../../modules/log-analytics"

  name                = module.naming.log_analytics_workspace
  resource_group_name = module.foundation_rg.name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.common_tags
}

module "foundation_vnet" {
  source = "../../modules/virtual-network"

  name                       = module.naming.virtual_network
  resource_group_name        = module.foundation_rg.name
  location                   = var.location
  address_space              = var.vnet_address_space
  enable_diagnostics         = true
  log_analytics_workspace_id = module.foundation_law.id
  tags                       = local.common_tags
}

module "foundation_nsg" {
  source = "../../modules/network-security-group"

  name                       = module.naming.network_security_group
  resource_group_name        = module.foundation_rg.name
  location                   = var.location
  enable_diagnostics         = true
  log_analytics_workspace_id = module.foundation_law.id
  tags                       = local.common_tags
  security_rules             = []
}

module "foundation_subnet" {
  source = "../../modules/subnet"

  name                      = module.naming.subnet
  resource_group_name       = module.foundation_rg.name
  virtual_network_name      = module.foundation_vnet.name
  address_prefixes          = var.subnet_address_prefixes
  enable_nsg_association    = true
  network_security_group_id = module.foundation_nsg.id
  service_endpoints         = ["Microsoft.KeyVault", "Microsoft.Storage"]
}

module "foundation_kv" {
  source = "../../modules/key-vault"

  name                          = module.naming.key_vault
  resource_group_name           = module.foundation_rg.name
  location                      = var.location
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true
  purge_protection_enabled      = false
  soft_delete_retention_days    = 7
  public_network_access_enabled = true
  network_acls_default_action   = "Allow"
  enable_diagnostics            = true
  log_analytics_workspace_id    = module.foundation_law.id
  tags                          = local.common_tags
}

module "foundation_storage" {
  source = "../../modules/storage-account"

  name                          = module.naming.storage_account
  resource_group_name           = module.foundation_rg.name
  location                      = var.location
  account_tier                  = "Standard"
  account_replication_type      = "LRS"
  public_network_access_enabled = true
  shared_access_key_enabled     = true
  network_rules_default_action  = "Allow"
  enable_diagnostics            = true
  log_analytics_workspace_id    = module.foundation_law.id
  tags                          = local.common_tags
}
