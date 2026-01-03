# ============================================================================
# STORAGE MODULE - OUTPUTS
# Healthcare Imaging MLOps Platform
# ============================================================================

output "training_data_bucket_id" {
  description = "ID of the training data bucket"
  value       = aws_s3_bucket.training_data.id
}

output "training_data_bucket_arn" {
  description = "ARN of the training data bucket"
  value       = aws_s3_bucket.training_data.arn
}

output "preprocessed_data_bucket_id" {
  description = "ID of the preprocessed data bucket"
  value       = aws_s3_bucket.preprocessed.id
}

output "preprocessed_data_bucket_arn" {
  description = "ARN of the preprocessed data bucket"
  value       = aws_s3_bucket.preprocessed.arn
}

output "model_artifacts_bucket_id" {
  description = "ID of the model artifacts bucket"
  value       = aws_s3_bucket.model_artifacts.id
}

output "model_artifacts_bucket_arn" {
  description = "ARN of the model artifacts bucket"
  value       = aws_s3_bucket.model_artifacts.arn
}

output "logs_bucket_id" {
  description = "ID of the logs bucket"
  value       = aws_s3_bucket.logs.id
}

output "logs_bucket_arn" {
  description = "ARN of the logs bucket"
  value       = aws_s3_bucket.logs.arn
}
