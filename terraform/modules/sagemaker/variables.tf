# ============================================================================
# AMAZON SAGEMAKER MODULE - VARIABLES
# Healthcare Imaging MLOps Platform
# ============================================================================

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "pipeline_name" {
  description = "Name of the SageMaker pipeline"
  type        = string
}

variable "sagemaker_role_name" {
  description = "Name of the SageMaker execution role"
  type        = string
}

variable "training_instance_type" {
  description = "Instance type for training jobs"
  type        = string
  default     = "ml.p3.2xlarge"
}

variable "processing_instance_type" {
  description = "Instance type for processing jobs"
  type        = string
  default     = "ml.m5.large"
}

variable "subnet_ids" {
  description = "Subnet IDs for SageMaker"
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security group IDs for SageMaker"
  type        = list(string)
}

variable "kms_key_id" {
  description = "KMS key ID for encryption"
  type        = string
}

variable "artifact_bucket" {
  description = "S3 bucket for model artifacts"
  type        = string
}

variable "training_data_bucket" {
  description = "S3 bucket for training data"
  type        = string
}

variable "enable_model_registry" {
  description = "Enable model registry"
  type        = bool
  default     = true
}

variable "model_package_group_name" {
  description = "Name of the model package group"
  type        = string
}

variable "training_container_uri" {
  description = "URI of the training container"
  type        = string
}

variable "processing_container_uri" {
  description = "URI of the processing container"
  type        = string
}

variable "create_sagemaker_domain" {
  description = "Create SageMaker domain"
  type        = bool
  default     = false
}

variable "vpc_id" {
  description = "VPC ID for SageMaker domain"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
