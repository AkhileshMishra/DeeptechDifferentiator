# ============================================================================
# EVENTBRIDGE MODULE - VARIABLES
# Healthcare Imaging MLOps Platform
# ============================================================================

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "event_bus_name" {
  description = "Name of the event bus"
  type        = string
}

variable "rules" {
  description = "Map of event rules"
  # FIXED: Updated types to allow optional 'input' and 'detail'
  type = map(object({
    description = string
    pattern = object({
      source      = list(string)
      detail-type = list(string)
      # CHANGE HERE: Use 'any' instead of 'map(any)' to handle nulls and objects better
      detail      = any
    })
    targets = list(object({
      arn      = string
      # Allow role_arn to be null (Lambdas don't need it)
      role_arn = optional(string)
      # Allow input to be passed (JSON string)
      input    = optional(string)
    }))
  }))
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
