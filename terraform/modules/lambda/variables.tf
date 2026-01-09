# ============================================================================
# LAMBDA MODULE - VARIABLES
# Healthcare Imaging MLOps Platform
# ============================================================================

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "functions" {
  description = "Lambda function configurations"
  type = map(object({
    description = string
    handler     = string
    runtime     = string
    timeout     = number
    memory_size = number
    zip_file    = string
  }))
}

variable "subnet_ids" {
  description = "Subnet IDs for Lambda VPC configuration"
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security group IDs for Lambda"
  type        = list(string)
}

variable "s3_bucket_arns" {
  description = "S3 bucket ARNs for Lambda access"
  type        = list(string)
}

variable "dynamodb_table_arns" {
  description = "DynamoDB table ARNs for Lambda access"
  type        = list(string)
}

variable "kms_key_arn" {
  description = "KMS key ARN for encryption"
  type        = string
}

variable "healthimaging_datastore_id" {
  description = "HealthImaging datastore ID"
  type        = string
}

variable "image_metadata_table" {
  description = "DynamoDB table name for image metadata"
  type        = string
}

variable "training_metrics_table" {
  description = "DynamoDB table name for training metrics"
  type        = string
}

variable "sagemaker_pipeline_arn" {
  description = "SageMaker pipeline ARN"
  type        = string
}

variable "model_artifacts_bucket" {
  description = "S3 bucket for model artifacts"
  type        = string
}

variable "model_package_group" {
  description = "SageMaker model package group name"
  type        = string
}

variable "training_data_bucket" {
  description = "S3 bucket for training data (DICOM input)"
  type        = string
  default     = ""
}

variable "healthimaging_import_role_arn" {
  description = "IAM role ARN for HealthImaging import jobs"
  type        = string
  default     = ""
}

variable "log_retention_days" {
  description = "CloudWatch log retention days"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
