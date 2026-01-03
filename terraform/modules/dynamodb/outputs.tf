# ============================================================================
# DYNAMODB MODULE - OUTPUTS
# Healthcare Imaging MLOps Platform
# ============================================================================

output "image_metadata_table_name" {
  description = "Name of the image metadata table"
  value       = aws_dynamodb_table.image_metadata.name
}

output "image_metadata_table_arn" {
  description = "ARN of the image metadata table"
  value       = aws_dynamodb_table.image_metadata.arn
}

output "training_metrics_table_name" {
  description = "Name of the training metrics table"
  value       = aws_dynamodb_table.training_metrics.name
}

output "training_metrics_table_arn" {
  description = "ARN of the training metrics table"
  value       = aws_dynamodb_table.training_metrics.arn
}

output "pipeline_state_table_name" {
  description = "Name of the pipeline state table"
  value       = aws_dynamodb_table.pipeline_state.name
}

output "pipeline_state_table_arn" {
  description = "ARN of the pipeline state table"
  value       = aws_dynamodb_table.pipeline_state.arn
}
