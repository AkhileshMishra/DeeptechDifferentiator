# ============================================================================
# SECURITY MODULE - VARIABLES
# Healthcare Imaging MLOps Platform
# ============================================================================

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "create_kms_key_s3" {
  description = "Create KMS key for S3"
  type        = bool
  default     = true
}

variable "create_kms_key_sagemaker" {
  description = "Create KMS key for SageMaker"
  type        = bool
  default     = true
}

variable "create_kms_key_logs" {
  description = "Create KMS key for CloudWatch Logs"
  type        = bool
  default     = true
}

variable "enable_secrets_manager" {
  description = "Enable Secrets Manager"
  type        = bool
  default     = false
}

variable "secrets" {
  description = "Map of secrets to create"
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
