# ============================================================================
# AWS HEALTHIMAGING MODULE
# Healthcare Imaging MLOps Platform
# ============================================================================

# ============================================================================
# HEALTHIMAGING DATA STORE (Using AWS Cloud Control Provider)
# ============================================================================

resource "awscc_healthimaging_datastore" "main" {
  # Maps the input variable "data_store_name" to the resource argument "datastore_name"
  datastore_name = var.data_store_name
  
  # Maps the input variable "kms_key_id" to the resource argument "kms_key_arn"
  kms_key_arn    = var.kms_key_id
  
  tags           = var.tags
}

# ============================================================================
# IAM ROLE FOR HEALTHIMAGING ACCESS
# ============================================================================

resource "aws_iam_role" "healthimaging_access" {
  name = "${var.name_prefix}-healthimaging-access-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = [
            "medical-imaging.amazonaws.com",
            "lambda.amazonaws.com",
            "sagemaker.amazonaws.com"
          ]
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "healthimaging_access" {
  name = "${var.name_prefix}-healthimaging-access-policy"
  role = aws_iam_role.healthimaging_access.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "medical-imaging:GetImageSet",
          "medical-imaging:GetImageFrame",
          "medical-imaging:GetImageSetMetadata",
          "medical-imaging:SearchImageSets"
        ]
        # FIXED: References the ARN from the awscc provider resource
        Resource = awscc_healthimaging_datastore.main.datastore_arn
      }
    ]
  })
}

# ============================================================================
# S3 BUCKET FOR DICOM INGESTION
# ============================================================================

resource "aws_s3_bucket" "dicom_ingestion" {
  bucket = "${var.name_prefix}-dicom-ingestion"
  force_destroy = true # Allow destruction for workshops

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-dicom-ingestion"
  })
}

resource "aws_s3_bucket_versioning" "dicom_ingestion" {
  bucket = aws_s3_bucket.dicom_ingestion.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "dicom_ingestion" {
  bucket = aws_s3_bucket.dicom_ingestion.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.kms_key_id
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "dicom_ingestion" {
  bucket = aws_s3_bucket.dicom_ingestion.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
