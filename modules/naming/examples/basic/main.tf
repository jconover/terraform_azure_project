module "naming" {
  source = "../../"

  project     = "platform"
  environment = "dev"
  location    = "eastus2"
  unique_seed = "00000000-0000-0000-0000-000000000000"
}

output "names" {
  value = {
    base_name       = module.naming.base_name
    location_short  = module.naming.location_short
    resource_group  = module.naming.resource_group
    virtual_network = module.naming.virtual_network
    subnet          = module.naming.subnet
    nsg             = module.naming.network_security_group
    storage_account = module.naming.storage_account
    key_vault       = module.naming.key_vault
    aks_cluster     = module.naming.aks_cluster
    log_analytics   = module.naming.log_analytics_workspace
    managed_id      = module.naming.managed_identity
    fabric          = module.naming.fabric_capacity
  }
}
