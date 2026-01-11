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

variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-1"
}

variable "healthimaging_datastore_arn" {
  description = "ARN of the HealthImaging datastore"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the KMS key used for HealthImaging encryption"
  type        = string
}

variable "dicom_upload_bucket_arn" {
  description = "ARN of the S3 bucket for DICOM uploads"
  type        = string
}

variable "callback_urls" {
  description = "Callback URLs for Cognito OAuth"
  type        = list(string)
  default     = ["http://localhost:3000/callback"]
}

variable "logout_urls" {
  description = "Logout URLs for Cognito"
  type        = list(string)
  default     = ["http://localhost:3000/"]
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
