# ============================================================================
# SECURITY MODULE
# Healthcare Imaging MLOps Platform
# ============================================================================

# ============================================================================
# KMS KEY FOR S3
# ============================================================================

resource "aws_kms_key" "s3" {
  count = var.create_kms_key_s3 ? 1 : 0

  description             = "KMS key for S3 encryption - ${var.name_prefix}"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow S3 Service"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-s3-kms"
  })
}

resource "aws_kms_alias" "s3" {
  count = var.create_kms_key_s3 ? 1 : 0

  name          = "alias/${var.name_prefix}-s3"
  target_key_id = aws_kms_key.s3[0].key_id
}

# ============================================================================
# KMS KEY FOR SAGEMAKER
# ============================================================================

resource "aws_kms_key" "sagemaker" {
  count = var.create_kms_key_sagemaker ? 1 : 0

  description             = "KMS key for SageMaker and HealthImaging encryption - ${var.name_prefix}"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow SageMaker Service"
        Effect = "Allow"
        Principal = {
          Service = "sagemaker.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "Allow HealthImaging Service"
        Effect = "Allow"
        Principal = {
          Service = "medical-imaging.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
          "kms:CreateGrant",
          "kms:RetireGrant"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-sagemaker-kms"
  })
}

resource "aws_kms_alias" "sagemaker" {
  count = var.create_kms_key_sagemaker ? 1 : 0

  name          = "alias/${var.name_prefix}-sagemaker"
  target_key_id = aws_kms_key.sagemaker[0].key_id
}

# ============================================================================
# KMS KEY FOR LOGS
# ============================================================================

resource "aws_kms_key" "logs" {
  count = var.create_kms_key_logs ? 1 : 0

  description             = "KMS key for CloudWatch Logs encryption - ${var.name_prefix}"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow CloudWatch Logs"
        Effect = "Allow"
        Principal = {
          Service = "logs.${data.aws_region.current.name}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
          }
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-logs-kms"
  })
}

resource "aws_kms_alias" "logs" {
  count = var.create_kms_key_logs ? 1 : 0

  name          = "alias/${var.name_prefix}-logs"
  target_key_id = aws_kms_key.logs[0].key_id
}

# ============================================================================
# SECRETS MANAGER
# ============================================================================

resource "aws_secretsmanager_secret" "secrets" {
  for_each = var.enable_secrets_manager ? nonsensitive(toset([for k, v in var.secrets : k if v != null && v != ""])) : toset([])

  name = "${var.name_prefix}-${each.key}"

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "secrets" {
  for_each = var.enable_secrets_manager ? nonsensitive(toset([for k, v in var.secrets : k if v != null && v != ""])) : toset([])

  secret_id     = aws_secretsmanager_secret.secrets[each.key].id
  secret_string = var.secrets[each.key]
}





# ============================================================================
# DATA SOURCES
# ============================================================================

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
