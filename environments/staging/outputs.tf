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
