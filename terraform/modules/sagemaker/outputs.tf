# ============================================================================
# AMAZON SAGEMAKER MODULE - OUTPUTS
# Healthcare Imaging MLOps Platform
# ============================================================================

output "pipeline_arn" {
  description = "ARN of the SageMaker pipeline"
  value       = aws_sagemaker_pipeline.training.arn
}

output "pipeline_name" {
  description = "Name of the SageMaker pipeline"
  value       = aws_sagemaker_pipeline.training.pipeline_name
}

output "sagemaker_execution_role_arn" {
  description = "ARN of the SageMaker execution role"
  value       = aws_iam_role.sagemaker_execution.arn
}

output "sagemaker_execution_role_name" {
  description = "Name of the SageMaker execution role"
  value       = aws_iam_role.sagemaker_execution.name
}

output "model_registry_arn" {
  description = "ARN of the model registry"
  value       = var.enable_model_registry ? aws_sagemaker_model_package_group.main[0].arn : null
}

output "model_registry_name" {
  description = "Name of the model registry"
  value       = var.enable_model_registry ? aws_sagemaker_model_package_group.main[0].model_package_group_name : null
}
