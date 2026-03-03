resource "azurerm_user_assigned_identity" "this" {
  count = var.type == "UserAssigned" ? 1 : 0

  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}
