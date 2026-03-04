terraform {
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "stterraform92d79d"
    container_name       = "tfstate"
    key                  = "staging.terraform.tfstate"
    use_oidc             = true
  }
}
