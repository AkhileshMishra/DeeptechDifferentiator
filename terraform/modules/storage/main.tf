# ============================================================================
# STORAGE MODULE
# Healthcare Imaging MLOps Platform
# ============================================================================

# ============================================================================
# TRAINING DATA BUCKET
# ============================================================================

resource "aws_s3_bucket" "training_data" {
  bucket = var.s3_buckets.training_data

  tags = merge(var.tags, {
    Name = var.s3_buckets.training_data
  })
}

resource "aws_s3_bucket_versioning" "training_data" {
  bucket = aws_s3_bucket.training_data.id
  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Disabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "training_data" {
  bucket = aws_s3_bucket.training_data.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.kms_key_id
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "training_data" {
  bucket = aws_s3_bucket.training_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "training_data" {
  bucket = aws_s3_bucket.training_data.id

  rule {
    id     = "training-data-lifecycle"
    status = "Enabled"
    filter {
      prefix = ""
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = var.training_data_retention_days
    }
  }
}

# ============================================================================
# PREPROCESSED DATA BUCKET
# ============================================================================

resource "aws_s3_bucket" "preprocessed" {
  bucket = var.s3_buckets.preprocessed

  tags = merge(var.tags, {
    Name = var.s3_buckets.preprocessed
  })
}

resource "aws_s3_bucket_versioning" "preprocessed" {
  bucket = aws_s3_bucket.preprocessed.id
  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Disabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "preprocessed" {
  bucket = aws_s3_bucket.preprocessed.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.kms_key_id
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "preprocessed" {
  bucket = aws_s3_bucket.preprocessed.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ============================================================================
# MODEL ARTIFACTS BUCKET
# ============================================================================

resource "aws_s3_bucket" "model_artifacts" {
  bucket = var.s3_buckets.model_artifacts

  tags = merge(var.tags, {
    Name = var.s3_buckets.model_artifacts
  })
}

resource "aws_s3_bucket_versioning" "model_artifacts" {
  bucket = aws_s3_bucket.model_artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "model_artifacts" {
  bucket = aws_s3_bucket.model_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.kms_key_id
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "model_artifacts" {
  bucket = aws_s3_bucket.model_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ============================================================================
# LOGS BUCKET
# ============================================================================

resource "aws_s3_bucket" "logs" {
  bucket = var.s3_buckets.logs

  tags = merge(var.tags, {
    Name = var.s3_buckets.logs
  })
}

resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.kms_key_id
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket = aws_s3_bucket.logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "logs-lifecycle"
    status = "Enabled"
    filter {
      prefix = ""
    }
    expiration {
      days = var.logs_retention_days
    }
  }
}
