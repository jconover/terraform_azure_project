resource "azurerm_policy_definition" "this" {
  for_each = var.policy_definitions

  name                = each.key
  policy_type         = "Custom"
  mode                = each.value.mode
  display_name        = each.value.display_name
  description         = each.value.description
  management_group_id = var.scope
  policy_rule         = each.value.policy_rule
  metadata            = each.value.metadata != "" ? each.value.metadata : null
  parameters          = each.value.parameters != "" ? each.value.parameters : null
}

resource "azurerm_subscription_policy_assignment" "this" {
  for_each = var.policy_assignments

  name                 = each.key
  policy_definition_id = each.value.policy_definition_id
  subscription_id      = each.value.scope
  display_name         = each.value.display_name
  description          = each.value.description
  enforce              = each.value.enforce
  parameters           = each.value.parameters != "" ? each.value.parameters : null
  location             = each.value.location != "" ? each.value.location : null

  dynamic "identity" {
    for_each = each.value.identity_type != "" ? [1] : []
    content {
      type = each.value.identity_type
    }
  }
}
