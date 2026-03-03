resource "azurerm_user_assigned_identity" "aks" {
  name                = "myapp-dev-eus2-aks-identity"
  resource_group_name = "myapp-dev-eus2-rg"
  location            = "eastus2"
}

module "aks_cluster" {
  source = "../../"

  name                = "myapp-dev-eus2-aks"
  resource_group_name = "myapp-dev-eus2-rg"
  location            = "eastus2"
  dns_prefix          = "myapp-dev"

  identity_type             = "UserAssigned"
  user_assigned_identity_id = azurerm_user_assigned_identity.aks.id

  default_node_pool = {
    name      = "system"
    vm_size   = "Standard_B2s"
    min_count = 1
    max_count = 3
    os_sku    = "AzureLinux"
  }

  network_plugin      = "azure"
  network_plugin_mode = "overlay"

  workload_identity_enabled = true
  oidc_issuer_enabled       = true
  azure_policy_enabled      = true

  tags = {
    Environment = "dev"
    Project     = "myapp"
  }
}

output "aks_cluster" {
  value = {
    id   = module.aks_cluster.id
    name = module.aks_cluster.name
    fqdn = module.aks_cluster.fqdn
  }
}
