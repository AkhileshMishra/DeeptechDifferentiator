# ============================================================================
# TERRAFORM OUTPUTS
# Healthcare Imaging MLOps Platform
# ============================================================================

# ============================================================================
# VPC & NETWORKING OUTPUTS
# ============================================================================

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.networking.vpc_id
}

output "private_subnet_ids" {
  description = "IDs of private subnets"
  value       = module.networking.private_subnet_ids
}

output "public_subnet_ids" {
  description = "IDs of public subnets"
  value       = module.networking.public_subnet_ids
}

# ============================================================================
# HEALTHIMAGING OUTPUTS
# ============================================================================

output "healthimaging_datastore_id" {
  description = "ID of the HealthImaging data store"
  value       = module.healthimaging.datastore_id
}

output "healthimaging_datastore_arn" {
  description = "ARN of the HealthImaging data store"
  value       = module.healthimaging.datastore_arn
}

# ============================================================================
# SAGEMAKER OUTPUTS
# ============================================================================

output "sagemaker_pipeline_arn" {
  description = "ARN of the SageMaker pipeline"
  value       = module.sagemaker.pipeline_arn
}

output "sagemaker_execution_role_arn" {
  description = "ARN of the SageMaker execution role"
  value       = module.sagemaker.sagemaker_execution_role_arn
}

output "model_registry_arn" {
  description = "ARN of the model registry"
  value       = module.sagemaker.model_registry_arn
}

# ============================================================================
# S3 BUCKET OUTPUTS
# ============================================================================

output "training_data_bucket" {
  description = "Name of the training data S3 bucket"
  value       = module.storage.training_data_bucket_id
}

output "model_artifacts_bucket" {
  description = "Name of the model artifacts S3 bucket"
  value       = module.storage.model_artifacts_bucket_id
}

output "preprocessed_data_bucket" {
  description = "Name of the preprocessed data S3 bucket"
  value       = module.storage.preprocessed_data_bucket_id
}

output "logs_bucket" {
  description = "Name of the logs S3 bucket"
  value       = module.storage.logs_bucket_id
}

# ============================================================================
# LAMBDA FUNCTION OUTPUTS
# ============================================================================

output "image_ingestion_function_arn" {
  description = "ARN of the image ingestion Lambda function"
  value       = module.lambda_functions.image_ingestion_function_arn
}

output "pipeline_trigger_function_arn" {
  description = "ARN of the pipeline trigger Lambda function"
  value       = module.lambda_functions.pipeline_trigger_function_arn
}

output "model_evaluation_function_arn" {
  description = "ARN of the model evaluation Lambda function"
  value       = module.lambda_functions.model_evaluation_function_arn
}

output "model_registry_function_arn" {
  description = "ARN of the model registry Lambda function"
  value       = module.lambda_functions.model_registry_function_arn
}

# ============================================================================
# EVENTBRIDGE OUTPUTS
# ============================================================================

output "event_bus_arn" {
  description = "ARN of the custom EventBridge event bus"
  value       = module.eventbridge.event_bus_arn
}

output "event_bus_name" {
  description = "Name of the custom EventBridge event bus"
  value       = module.eventbridge.event_bus_name
}

# ============================================================================
# DYNAMODB OUTPUTS
# ============================================================================

output "image_metadata_table_name" {
  description = "Name of the image metadata DynamoDB table"
  value       = module.dynamodb.image_metadata_table_name
}

output "training_metrics_table_name" {
  description = "Name of the training metrics DynamoDB table"
  value       = module.dynamodb.training_metrics_table_name
}

# ============================================================================
# ECR OUTPUTS
# ============================================================================

output "ecr_repository_urls" {
  description = "URLs of ECR repositories"
  value       = module.ecr.repository_urls
}

# ============================================================================
# SECURITY OUTPUTS
# ============================================================================

output "s3_kms_key_arn" {
  description = "ARN of the S3 KMS key"
  value       = module.security.s3_kms_key_arn
}

output "sagemaker_kms_key_arn" {
  description = "ARN of the SageMaker KMS key"
  value       = module.security.sagemaker_kms_key_arn
}

# ============================================================================
# MONITORING OUTPUTS
# ============================================================================

output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value       = module.monitoring.dashboard_url
}

output "cloudwatch_log_group_names" {
  description = "Names of CloudWatch log groups"
  value       = module.monitoring.log_group_names
}

# ============================================================================
# DEPLOYMENT SUMMARY
# ============================================================================

output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    environment          = var.environment
    region               = var.aws_region
    vpc_id               = module.networking.vpc_id
    healthimaging_store  = module.healthimaging.datastore_id
    sagemaker_pipeline   = module.sagemaker.pipeline_arn
    training_bucket      = module.storage.training_data_bucket_id
    model_bucket         = module.storage.model_artifacts_bucket_id
  }
}
