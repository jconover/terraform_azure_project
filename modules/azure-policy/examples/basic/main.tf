data "azurerm_subscription" "current" {}

module "azure_policy" {
  source = "../../"

  scope = data.azurerm_subscription.current.id

  policy_definitions = {
    require-tags = {
      display_name = "Require environment tag on all resources"
      description  = "Denies creation of resources that do not have an environment tag"
      policy_rule = jsonencode({
        if = {
          field  = "[concat('tags[', 'environment', ']')]"
          exists = "false"
        }
        then = {
          effect = "deny"
        }
      })
    }

    deny-public-storage = {
      display_name = "Deny public blob access on storage accounts"
      description  = "Denies storage accounts that have public blob access enabled"
      mode         = "All"
      policy_rule = jsonencode({
        if = {
          allOf = [
            {
              field  = "type"
              equals = "Microsoft.Storage/storageAccounts"
            },
            {
              field     = "Microsoft.Storage/storageAccounts/allowBlobPublicAccess"
              notEquals = "false"
            }
          ]
        }
        then = {
          effect = "deny"
        }
      })
    }

    enforce-https = {
      display_name = "Audit resources not using HTTPS"
      description  = "Audits resources that are not configured to use HTTPS"
      policy_rule = jsonencode({
        if = {
          allOf = [
            {
              field  = "type"
              equals = "Microsoft.Web/sites"
            },
            {
              field     = "Microsoft.Web/sites/httpsOnly"
              notEquals = "true"
            }
          ]
        }
        then = {
          effect = "audit"
        }
      })
    }
  }

  policy_assignments = {
    assign-require-tags = {
      policy_definition_id = module.azure_policy.policy_definition_ids["require-tags"]
      display_name         = "Require environment tag"
      description          = "Ensures all resources have an environment tag"
      scope                = data.azurerm_subscription.current.id
      enforce              = true
    }

    assign-deny-public-storage = {
      policy_definition_id = module.azure_policy.policy_definition_ids["deny-public-storage"]
      display_name         = "Deny public storage accounts"
      description          = "Prevents creation of storage accounts with public blob access"
      scope                = data.azurerm_subscription.current.id
      enforce              = true
    }

    assign-enforce-https = {
      policy_definition_id = module.azure_policy.policy_definition_ids["enforce-https"]
      display_name         = "Audit non-HTTPS resources"
      description          = "Audits web apps not configured for HTTPS"
      scope                = data.azurerm_subscription.current.id
      enforce              = false
    }
  }
}

output "policy_definition_ids" {
  value = module.azure_policy.policy_definition_ids
}

output "policy_assignment_ids" {
  value = module.azure_policy.policy_assignment_ids
}
