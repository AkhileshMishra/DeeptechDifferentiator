# ============================================================================
# LAMBDA MODULE - OUTPUTS
# Healthcare Imaging MLOps Platform
# ============================================================================

output "image_ingestion_function_arn" {
  description = "ARN of the image ingestion Lambda function"
  value       = aws_lambda_function.image_ingestion.arn
}

output "image_ingestion_function_name" {
  description = "Name of the image ingestion Lambda function"
  value       = aws_lambda_function.image_ingestion.function_name
}

output "image_ingestion_role_arn" {
  description = "ARN of the image ingestion Lambda role"
  value       = aws_iam_role.lambda_execution.arn
}

output "pipeline_trigger_function_arn" {
  description = "ARN of the pipeline trigger Lambda function"
  value       = aws_lambda_function.pipeline_trigger.arn
}

output "pipeline_trigger_function_name" {
  description = "Name of the pipeline trigger Lambda function"
  value       = aws_lambda_function.pipeline_trigger.function_name
}

output "model_evaluation_function_arn" {
  description = "ARN of the model evaluation Lambda function"
  value       = aws_lambda_function.model_evaluation.arn
}

output "model_evaluation_function_name" {
  description = "Name of the model evaluation Lambda function"
  value       = aws_lambda_function.model_evaluation.function_name
}

output "model_registry_function_arn" {
  description = "ARN of the model registry Lambda function"
  value       = aws_lambda_function.model_registry.arn
}

output "model_registry_function_name" {
  description = "Name of the model registry Lambda function"
  value       = aws_lambda_function.model_registry.function_name
}

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role"
  value       = aws_iam_role.lambda_execution.arn
}
