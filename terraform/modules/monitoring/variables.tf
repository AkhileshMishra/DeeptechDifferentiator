# ============================================================================
# MONITORING MODULE - VARIABLES
# Healthcare Imaging MLOps Platform
# ============================================================================

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "log_retention_days" {
  description = "CloudWatch log retention days"
  type        = number
  default     = 30
}

variable "training_data_bucket" {
  description = "Training data S3 bucket name"
  type        = string
}

variable "model_artifacts_bucket" {
  description = "Model artifacts S3 bucket name"
  type        = string
}

variable "alarm_actions" {
  description = "List of ARNs for alarm actions"
  type        = list(string)
  default     = []
}

variable "alert_email" {
  description = "Email address for alerts"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
