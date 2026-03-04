variable "policy_definitions" {
  description = "Map of custom policy definitions to create"
  type = map(object({
    display_name = string
    description  = optional(string, "")
    mode         = optional(string, "All")
    policy_rule  = string
    metadata     = optional(string, "")
    parameters   = optional(string, "")
  }))
  default = {}
}

variable "policy_assignments" {
  description = "Map of policy assignments to create"
  type = map(object({
    policy_definition_id = string
    display_name         = string
    description          = optional(string, "")
    scope                = string
    parameters           = optional(string, "")
    enforce              = optional(bool, true)
    identity_type        = optional(string, "")
    location             = optional(string, "")
  }))
  default = {}
}


variable "scope" {
  description = "Default scope for policy definitions (subscription or management group ID)"
  type        = string
}
