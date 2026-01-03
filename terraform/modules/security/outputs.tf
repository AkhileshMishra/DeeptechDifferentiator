# ============================================================================
# SECURITY MODULE - OUTPUTS
# Healthcare Imaging MLOps Platform
# ============================================================================

output "s3_kms_key_id" {
  description = "ID of the S3 KMS key"
  value       = var.create_kms_key_s3 ? aws_kms_key.s3[0].key_id : null
}

output "s3_kms_key_arn" {
  description = "ARN of the S3 KMS key"
  value       = var.create_kms_key_s3 ? aws_kms_key.s3[0].arn : null
}

output "sagemaker_kms_key_id" {
  description = "ID of the SageMaker KMS key"
  value       = var.create_kms_key_sagemaker ? aws_kms_key.sagemaker[0].key_id : null
}

output "sagemaker_kms_key_arn" {
  description = "ARN of the SageMaker KMS key"
  value       = var.create_kms_key_sagemaker ? aws_kms_key.sagemaker[0].arn : null
}

output "logs_kms_key_id" {
  description = "ID of the CloudWatch Logs KMS key"
  value       = var.create_kms_key_logs ? aws_kms_key.logs[0].key_id : null
}

output "logs_kms_key_arn" {
  description = "ARN of the CloudWatch Logs KMS key"
  value       = var.create_kms_key_logs ? aws_kms_key.logs[0].arn : null
}

output "secret_arns" {
  description = "ARNs of created secrets"
  value       = { for k, v in aws_secretsmanager_secret.secrets : k => v.arn }
}
