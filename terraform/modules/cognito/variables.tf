# ============================================================================
# COGNITO MODULE - VARIABLES
# ============================================================================

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "aws_account_id" {
  description = "AWS Account ID"
  type        = string
}

variable "healthimaging_datastore_arn" {
  description = "ARN of the HealthImaging datastore"
  type        = string
}

variable "callback_urls" {
  description = "Callback URLs for Cognito"
  type        = list(string)
  default     = ["http://localhost:8080/", "http://localhost:3000/"]
}

variable "logout_urls" {
  description = "Logout URLs for Cognito"
  type        = list(string)
  default     = ["http://localhost:8080/", "http://localhost:3000/"]
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
