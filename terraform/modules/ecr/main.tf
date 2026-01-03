# ============================================================================
# ECR MODULE
# Healthcare Imaging MLOps Platform
# ============================================================================

# ============================================================================
# ECR REPOSITORIES
# ============================================================================

resource "aws_ecr_repository" "repos" {
  for_each = toset(var.repositories)

  name                 = "${var.name_prefix}-${each.value}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = var.image_scan_on_push
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-${each.value}"
  })
}

# ============================================================================
# LIFECYCLE POLICIES
# ============================================================================

resource "aws_ecr_lifecycle_policy" "repos" {
  for_each = toset(var.repositories)

  repository = aws_ecr_repository.repos[each.value].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last ${var.max_image_count} images"
        selection = {
          tagStatus     = "any"
          countType     = "imageCountMoreThan"
          countNumber   = var.max_image_count
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Expire untagged images older than ${var.image_retention_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.image_retention_days
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# ============================================================================
# REPOSITORY POLICIES
# ============================================================================

resource "aws_ecr_repository_policy" "repos" {
  for_each = toset(var.repositories)

  repository = aws_ecr_repository.repos[each.value].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowSageMakerAccess"
        Effect = "Allow"
        Principal = {
          Service = "sagemaker.amazonaws.com"
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
      },
      {
        Sid    = "AllowLambdaAccess"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
      }
    ]
  })
}
