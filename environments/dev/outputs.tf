output "naming" {
  description = "Generated resource names from the naming module"
  value = {
    resource_group  = module.naming.resource_group
    virtual_network = module.naming.virtual_network
    storage_account = module.naming.storage_account
    aks_cluster     = module.naming.aks_cluster
    key_vault       = module.naming.key_vault
  }
}

output "resource_group" {
  description = "Foundation resource group details"
  value = {
    id       = module.foundation_rg.id
    name     = module.foundation_rg.name
    location = module.foundation_rg.location
  }
}

output "log_analytics" {
  description = "Log Analytics workspace details"
  value = {
    id           = module.foundation_law.id
    name         = module.foundation_law.name
    workspace_id = module.foundation_law.workspace_id
  }
}

output "virtual_network" {
  description = "Virtual network details"
  value = {
    id            = module.foundation_vnet.id
    name          = module.foundation_vnet.name
    address_space = module.foundation_vnet.address_space
  }
}

output "key_vault" {
  description = "Key Vault details"
  value = {
    id        = module.foundation_kv.id
    name      = module.foundation_kv.name
    vault_uri = module.foundation_kv.vault_uri
  }
}

output "storage_account" {
  description = "Storage account details"
  value = {
    id   = module.foundation_storage.id
    name = module.foundation_storage.name
  }
}
