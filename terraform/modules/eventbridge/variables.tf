# ============================================================================
# EVENTBRIDGE MODULE - VARIABLES
# Healthcare Imaging MLOps Platform
# ============================================================================

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "event_bus_name" {
  description = "Name of the custom event bus"
  type        = string
}

variable "rules" {
  description = "Map of event rules"
  type = map(object({
    description = string
    pattern = object({
      source      = list(string)
      detail-type = list(string)
      detail      = optional(map(any))
    })
    targets = list(object({
      arn      = string
      role_arn = string
    }))
  }))
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
