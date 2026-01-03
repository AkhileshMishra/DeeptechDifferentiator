# ============================================================================
# AWS HEALTHIMAGING MODULE - OUTPUTS
# Healthcare Imaging MLOps Platform
# ============================================================================

output "datastore_id" {
  description = "ID of the HealthImaging data store"
  value       = aws_medical_imaging_datastore.main.id
}

output "datastore_arn" {
  description = "ARN of the HealthImaging data store"
  value       = aws_medical_imaging_datastore.main.arn
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
