# ============================================================================
# AWS HEALTHIMAGING MODULE - OUTPUTS
# Healthcare Imaging MLOps Platform
# ============================================================================

output "data_store_id" {
  description = "ID of the HealthImaging data store"
  # FIXED: awscc resource uses 'datastore_id'
  value       = awscc_healthimaging_datastore.main.datastore_id
}

output "data_store_arn" {
  description = "ARN of the HealthImaging data store"
  # FIXED: awscc resource uses 'datastore_arn'
  value       = awscc_healthimaging_datastore.main.datastore_arn
}

output "access_role_arn" {
  description = "ARN of the HealthImaging access role"
  value       = aws_iam_role.healthimaging_access.arn
}

output "dicom_ingestion_bucket_id" {
  description = "ID of the DICOM ingestion bucket"
  value       = aws_s3_bucket.dicom_ingestion.id
}

output "dicom_ingestion_bucket_arn" {
  description = "ARN of the DICOM ingestion bucket"
  value       = aws_s3_bucket.dicom_ingestion.arn
}
