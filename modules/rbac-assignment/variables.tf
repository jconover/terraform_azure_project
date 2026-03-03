variable "role_assignments" {
  description = "Map of role assignments to create. Key is a friendly name for identification."
  type = map(object({
    scope                = string
    role_definition_name = string
    principal_id         = string
    principal_type       = optional(string, "ServicePrincipal")
    description          = optional(string, "")
  }))
}

variable "custom_role_definitions" {
  description = "Map of custom role definitions to create."
  type = map(object({
    name        = string
    scope       = string
    description = optional(string, "")
    permissions = object({
      actions          = list(string)
      not_actions      = optional(list(string), [])
      data_actions     = optional(list(string), [])
      not_data_actions = optional(list(string), [])
    })
    assignable_scopes = list(string)
  }))
  default = {}
}
