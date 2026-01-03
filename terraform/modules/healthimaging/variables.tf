# ============================================================================
# AWS HEALTHIMAGING MODULE - VARIABLES
# Healthcare Imaging MLOps Platform
# ============================================================================

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "data_store_name" {
  description = "Name of the HealthImaging data store"
  type        = string
}

variable "kms_key_id" {
  description = "KMS key ID for encryption"
  type        = string
}

variable "allowed_principals" {
  description = "List of IAM principals allowed to access the data store"
  type        = list(string)
  default     = []
}

variable "dicom_ingestion_bucket" {
  description = "S3 bucket for DICOM ingestion"
  type        = string
}

variable "enable_logging" {
  description = "Enable CloudWatch logging"
  type        = bool
  default     = true
}

variable "log_group_name" {
  description = "CloudWatch log group name"
  type        = string
  default     = "/aws/healthimaging/default"
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
