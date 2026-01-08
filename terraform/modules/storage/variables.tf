# ============================================================================
# STORAGE MODULE - VARIABLES
# Healthcare Imaging MLOps Platform
# ============================================================================

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "s3_buckets" {
  description = "Map of S3 bucket names"
  type = object({
    training_data   = string
    preprocessed    = string
    model_artifacts = string
    logs            = string
  })
}

variable "kms_key_id" {
  description = "KMS key ID for encryption"
  type        = string
}

variable "enable_versioning" {
  description = "Enable S3 versioning"
  type        = bool
  default     = true
}

variable "training_data_retention_days" {
  description = "Retention days for training data"
  type        = number
  default     = 90
}

variable "logs_retention_days" {
  description = "Retention days for logs"
  type        = number
  default     = 30
}

variable "allow_healthimaging_access" {
  description = "Allow HealthImaging access to buckets"
  type        = bool
  default     = true
}

variable "allow_sagemaker_access" {
  description = "Allow SageMaker access to buckets"
  type        = bool
  default     = true
}

variable "vpc_id" {
  description = "VPC ID for bucket policies"
  type        = string
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
