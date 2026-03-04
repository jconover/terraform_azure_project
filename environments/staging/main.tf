locals {
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

# Phase 1: Foundation resources
# module "foundation_rg" { ... }
# module "foundation_vnet" { ... }
# module "foundation_kv" { ... }
# module "foundation_law" { ... }
