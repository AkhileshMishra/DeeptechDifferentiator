# ============================================================================
# DYNAMODB MODULE
# Healthcare Imaging MLOps Platform
# ============================================================================

# ============================================================================
# IMAGE METADATA TABLE
# ============================================================================

resource "aws_dynamodb_table" "image_metadata" {
  name           = "${var.name_prefix}-image-metadata"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "image_id"
  range_key      = "timestamp"

  attribute {
    name = "image_id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

  attribute {
    name = "patient_id"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  global_secondary_index {
    name               = "patient-index"
    hash_key           = "patient_id"
    range_key          = "timestamp"
    projection_type    = "ALL"
  }

  global_secondary_index {
    name               = "status-index"
    hash_key           = "status"
    range_key          = "timestamp"
    projection_type    = "ALL"
  }

  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }

  ttl {
    attribute_name = "ttl"
    enabled        = var.enable_ttl
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-image-metadata"
  })
}

# ============================================================================
# TRAINING METRICS TABLE
# ============================================================================

resource "aws_dynamodb_table" "training_metrics" {
  name           = "${var.name_prefix}-training-metrics"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "pipeline_execution_id"
  range_key      = "metric_name"

  attribute {
    name = "pipeline_execution_id"
    type = "S"
  }

  attribute {
    name = "metric_name"
    type = "S"
  }

  attribute {
    name = "model_version"
    type = "S"
  }

  global_secondary_index {
    name               = "model-version-index"
    hash_key           = "model_version"
    range_key          = "metric_name"
    projection_type    = "ALL"
  }

  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-training-metrics"
  })
}

# ============================================================================
# PIPELINE STATE TABLE
# ============================================================================

resource "aws_dynamodb_table" "pipeline_state" {
  name           = "${var.name_prefix}-pipeline-state"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "execution_id"

  attribute {
    name = "execution_id"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  global_secondary_index {
    name               = "status-index"
    hash_key           = "status"
    projection_type    = "ALL"
  }

  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-pipeline-state"
  })
}
