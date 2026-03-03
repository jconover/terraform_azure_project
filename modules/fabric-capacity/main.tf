resource "azurerm_fabric_capacity" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location

  sku {
    name = var.sku
    tier = "Fabric"
  }

  administration_members = var.admin_members
  tags                   = var.tags
}
