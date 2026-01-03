# ============================================================================
# ECR MODULE - OUTPUTS
# Healthcare Imaging MLOps Platform
# ============================================================================

output "repository_urls" {
  description = "URLs of ECR repositories"
  value       = { for k, v in aws_ecr_repository.repos : k => v.repository_url }
}

output "repository_arns" {
  description = "ARNs of ECR repositories"
  value       = { for k, v in aws_ecr_repository.repos : k => v.arn }
}

output "repository_names" {
  description = "Names of ECR repositories"
  value       = { for k, v in aws_ecr_repository.repos : k => v.name }
}
