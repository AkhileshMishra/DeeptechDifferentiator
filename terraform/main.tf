# terraform/main.tf
## Healthcare Imaging MLOps Platform - Infrastructure as Code
## AWS HealthImaging + SageMaker Pipelines Integration
## Module 3: Rapid Remote Triage & Continuous Model Improvement

terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote state backend (S3 + DynamoDB lock)
  backend "s3" {
    bucket         = "terraform-state-healthcare-imaging"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment   = var.environment
      Project       = var.project_name
      Module        = "module-3"
      CreatedBy     = "Terraform"
      CreatedDate   = timestamp()
      CostCenter    = var.cost_center
    }
  }
}

# Data source: Current AWS account
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ============================================================================
# SECTION 1: NETWORKING & SECURITY
# ============================================================================

# KMS Key for encryption at rest
resource "aws_kms_key" "healthcare_imaging" {
  description             = "KMS key for healthcare imaging encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name = "healthcare-imaging-key"
  }
}

resource "aws_kms_alias" "healthcare_imaging" {
  name          = "alias/healthcare-imaging-key"
  target_key_id = aws_kms_key.healthcare_imaging.key_id
}

# VPC for isolated networking
resource "aws_vpc" "healthcare_imaging" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "healthcare-imaging-vpc"
  }
}

# Private subnets (2 AZs)
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.healthcare_imaging.id
  cidr_block        = "10.0.${count.index + 1}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "healthcare-imaging-private-${count.index + 1}"
  }
}

# Public subnets for NAT gateways
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.healthcare_imaging.id
  cidr_block              = "10.0.${count.index + 11}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "healthcare-imaging-public-${count.index + 1}"
  }
}

# Get available AZs
data "aws_availability_zones" "available" {
  state = "available"
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.healthcare_imaging.id

  tags = {
    Name = "healthcare-imaging-igw"
  }
}

# NAT Gateways for private subnet internet access
resource "aws_eip" "nat" {
  count  = 2
  domain = "vpc"

  tags = {
    Name = "healthcare-imaging-nat-eip-${count.index + 1}"
  }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  count         = 2
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "healthcare-imaging-nat-${count.index + 1}"
  }

  depends_on = [aws_internet_gateway.main]
}

# Route tables
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.healthcare_imaging.id

  route {
    cidr_block      = "0.0.0.0/0"
    gateway_id      = aws_internet_gateway.main.id
  }

  tags = {
    Name = "healthcare-imaging-public-rt"
  }
}

resource "aws_route_table" "private" {
  count  = 2
  vpc_id = aws_vpc.healthcare_imaging.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = {
    Name = "healthcare-imaging-private-rt-${count.index + 1}"
  }
}

# Route table associations
resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# Security groups
resource "aws_security_group" "lambda" {
  name        = "healthcare-imaging-lambda-sg"
  description = "Security group for Lambda functions"
  vpc_id      = aws_vpc.healthcare_imaging.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "healthcare-imaging-lambda-sg"
  }
}

resource "aws_security_group" "sagemaker" {
  name        = "healthcare-imaging-sagemaker-sg"
  description = "Security group for SageMaker endpoints"
  vpc_id      = aws_vpc.healthcare_imaging.id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "healthcare-imaging-sagemaker-sg"
  }
}

# VPC Endpoints (for private service access without internet)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.healthcare_imaging.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = concat(
    [aws_route_table.public.id],
    aws_route_table.private[*].id
  )

  tags = {
    Name = "healthcare-imaging-s3-endpoint"
  }
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.healthcare_imaging.id
  service_name      = "com.amazonaws.${var.aws_region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = concat(
    [aws_route_table.public.id],
    aws_route_table.private[*].id
  )

  tags = {
    Name = "healthcare-imaging-dynamodb-endpoint"
  }
}

resource "aws_vpc_endpoint" "sagemaker_runtime" {
  vpc_id              = aws_vpc.healthcare_imaging.id
  service_name        = "com.amazonaws.${var.aws_region}.sagemaker.runtime"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.lambda.id]
  private_dns_enabled = true

  tags = {
    Name = "healthcare-imaging-sagemaker-runtime-endpoint"
  }
}

# ============================================================================
# SECTION 2: STORAGE
# ============================================================================

# S3 bucket for training data
resource "aws_s3_bucket" "training_data" {
  bucket              = "${var.project_name}-training-${data.aws_caller_identity.current.account_id}"
  force_destroy       = var.environment == "dev" ? true : false

  tags = {
    Name = "${var.project_name}-training-bucket"
  }
}

# Enable versioning
resource "aws_s3_bucket_versioning" "training_data" {
  bucket = aws_s3_bucket.training_data.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Enable encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "training_data" {
  bucket = aws_s3_bucket.training_data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.healthcare_imaging.arn
    }
    bucket_key_enabled = true
  }
}

# Block public access
resource "aws_s3_bucket_public_access_block" "training_data" {
  bucket                  = aws_s3_bucket.training_data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable access logging
resource "aws_s3_bucket_logging" "training_data" {
  bucket = aws_s3_bucket.training_data.id

  target_bucket = aws_s3_bucket.access_logs.id
  target_prefix = "training-data-logs/"
}

# Lifecycle policy (archive old data)
resource "aws_s3_bucket_lifecycle_configuration" "training_data" {
  bucket = aws_s3_bucket.training_data.id

  rule {
    id     = "archive-old-data"
    status = "Enabled"

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = 365
    }
  }
}

# S3 bucket for models
resource "aws_s3_bucket" "models" {
  bucket        = "${var.project_name}-models-${data.aws_caller_identity.current.account_id}"
  force_destroy = var.environment == "dev" ? true : false

  tags = {
    Name = "${var.project_name}-models-bucket"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "models" {
  bucket = aws_s3_bucket.models.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.healthcare_imaging.arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "models" {
  bucket                  = aws_s3_bucket.models.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket for logs
resource "aws_s3_bucket" "access_logs" {
  bucket        = "${var.project_name}-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = var.environment == "dev" ? true : false

  tags = {
    Name = "${var.project_name}-logs-bucket"
  }
}

resource "aws_s3_bucket_public_access_block" "access_logs" {
  bucket                  = aws_s3_bucket.access_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ============================================================================
# SECTION 3: AWS HEALTHIMAGING
# ============================================================================

# HealthImaging Datastore
resource "aws_healthimaging_datastore" "main" {
  datastore_name = "${var.project_name}-datastore"

  tags = {
    Name = "${var.project_name}-datastore"
  }
}

# ============================================================================
# SECTION 4: DYNAMODB (METADATA & METRICS)
# ============================================================================

# DynamoDB table for image metadata
resource "aws_dynamodb_table" "image_metadata" {
  name           = "${var.project_name}-metadata"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "image_id"
  range_key      = "timestamp"

  attribute {
    name = "image_id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "N"
  }

  attribute {
    name = "status"
    type = "S"
  }

  global_secondary_index {
    name            = "status-index"
    hash_key        = "status"
    projection_type = "ALL"
  }

  stream_specification {
    stream_view_type = "NEW_AND_OLD_IMAGES"
  }

  point_in_time_recovery_specification {
    enabled = true
  }

  ttl {
    attribute_name = "expiration_time"
    enabled        = true
  }

  tags = {
    Name = "${var.project_name}-metadata"
  }
}

# DynamoDB table for training metrics
resource "aws_dynamodb_table" "training_metrics" {
  name           = "${var.project_name}-metrics"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "pipeline_execution_id"
  range_key      = "metric_timestamp"

  attribute {
    name = "pipeline_execution_id"
    type = "S"
  }

  attribute {
    name = "metric_timestamp"
    type = "N"
  }

  stream_specification {
    stream_view_type = "NEW_AND_OLD_IMAGES"
  }

  point_in_time_recovery_specification {
    enabled = true
  }

  tags = {
    Name = "${var.project_name}-metrics"
  }
}

# ============================================================================
# SECTION 5: IAM ROLES & POLICIES
# ============================================================================

# Role for Lambda functions
resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-lambda-role"
  }
}

# Attach basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Custom policy for Lambda
resource "aws_iam_role_policy" "lambda_custom" {
  name   = "${var.project_name}-lambda-policy"
  role   = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # S3 access
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.training_data.arn,
          "${aws_s3_bucket.training_data.arn}/*",
          aws_s3_bucket.models.arn,
          "${aws_s3_bucket.models.arn}/*"
        ]
      }
      # HealthImaging access
      {
        Effect = "Allow"
        Action = [
          "healthimaging:GetImageSet",
          "healthimaging:StartDICOMImportJob",
          "healthimaging:ListImageSets",
          "healthimaging:SearchImageSets"
        ]
        Resource = "*"
      }
      # DynamoDB access
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          aws_dynamodb_table.image_metadata.arn,
          aws_dynamodb_table.training_metrics.arn
        ]
      }
      # SageMaker access
      {
        Effect = "Allow"
        Action = [
          "sagemaker:StartPipelineExecution",
          "sagemaker:DescribePipelineExecution",
          "sagemaker:ListPipelineExecutions"
        ]
        Resource = "*"
      }
      # CloudWatch Logs
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/*"
      }
      # KMS encryption
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = aws_kms_key.healthcare_imaging.arn
      }
    ]
  })
}

# Role for SageMaker
resource "aws_iam_role" "sagemaker_role" {
  name = "${var.project_name}-sagemaker-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "sagemaker.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-sagemaker-role"
  }
}

# Attach SageMaker execution policy
resource "aws_iam_role_policy_attachment" "sagemaker_basic" {
  role       = aws_iam_role.sagemaker_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}

# Custom SageMaker policy
resource "aws_iam_role_policy" "sagemaker_custom" {
  name   = "${var.project_name}-sagemaker-policy"
  role   = aws_iam_role.sagemaker_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # ECR access
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ]
        Resource = "*"
      }
      # S3 access
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.training_data.arn,
          "${aws_s3_bucket.training_data.arn}/*",
          aws_s3_bucket.models.arn,
          "${aws_s3_bucket.models.arn}/*"
        ]
      }
      # KMS encryption
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.healthcare_imaging.arn
      }
    ]
  })
}

# Role for EventBridge
resource "aws_iam_role" "eventbridge_role" {
  name = "${var.project_name}-eventbridge-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "eventbridge_policy" {
  name   = "${var.project_name}-eventbridge-policy"
  role   = aws_iam_role.eventbridge_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${var.project_name}-*"
      }
    ]
  })
}

# ============================================================================
# SECTION 6: LAMBDA FUNCTIONS
# ============================================================================

# Lambda Layer for common libraries
resource "aws_lambda_layer_version" "libraries" {
  filename   = "lambda-layers.zip"
  layer_name = "${var.project_name}-libraries"

  source_code_hash = filebase64sha256("lambda-layers.zip")

  compatible_runtimes = ["python3.11", "python3.12"]
}

# Lambda 1: Image Ingestion
resource "aws_lambda_function" "image_ingestion" {
  function_name = "${var.project_name}-image-ingestion"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 300
  memory_size   = 1024

  filename         = "lambda_functions/image_ingestion.zip"
  source_code_hash = filebase64sha256("lambda_functions/image_ingestion.zip")

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  layers = [aws_lambda_layer_version.libraries.arn]

  environment {
    variables = {
      HEALTHIMAGING_DATASTORE_ID = aws_healthimaging_datastore.main.datastore_id
      METADATA_TABLE              = aws_dynamodb_table.image_metadata.name
      ENVIRONMENT                 = var.environment
    }
  }

  tags = {
    Name = "${var.project_name}-image-ingestion"
  }
}

# S3 event notification to Lambda
resource "aws_s3_bucket_notification" "training_data" {
  bucket = aws_s3_bucket.training_data.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.image_ingestion.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "upload/"
  }

  depends_on = [aws_lambda_permission.s3_invoke]
}

resource "aws_lambda_permission" "s3_invoke" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.image_ingestion.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.training_data.arn
}

# Lambda 2: Pipeline Trigger
resource "aws_lambda_function" "pipeline_trigger" {
  function_name = "${var.project_name}-pipeline-trigger"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 60
  memory_size   = 256

  filename         = "lambda_functions/pipeline_trigger.zip"
  source_code_hash = filebase64sha256("lambda_functions/pipeline_trigger.zip")

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      SAGEMAKER_PIPELINE_NAME = aws_sagemaker_pipeline.main.pipeline_name
      ENVIRONMENT             = var.environment
    }
  }

  tags = {
    Name = "${var.project_name}-pipeline-trigger"
  }
}

resource "aws_lambda_permission" "eventbridge_invoke" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.pipeline_trigger.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.image_verified.arn
}

# Lambda 3: Model Evaluation
resource "aws_lambda_function" "model_evaluation" {
  function_name = "${var.project_name}-model-evaluation"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 120
  memory_size   = 512

  filename         = "lambda_functions/model_evaluation.zip"
  source_code_hash = filebase64sha256("lambda_functions/model_evaluation.zip")

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      METRICS_TABLE = aws_dynamodb_table.training_metrics.name
      MODELS_BUCKET = aws_s3_bucket.models.id
      ENVIRONMENT   = var.environment
    }
  }

  tags = {
    Name = "${var.project_name}-model-evaluation"
  }
}

# Lambda 4: Model Registry
resource "aws_lambda_function" "model_registry" {
  function_name = "${var.project_name}-model-registry"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 60
  memory_size   = 256

  filename         = "lambda_functions/model_registry.zip"
  source_code_hash = filebase64sha256("lambda_functions/model_registry.zip")

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      SAGEMAKER_REGISTRY_ARN = aws_sagemaker_model_package_group.main.arn
      ENVIRONMENT            = var.environment
    }
  }

  tags = {
    Name = "${var.project_name}-model-registry"
  }
}

# ============================================================================
# SECTION 7: EVENTBRIDGE (ORCHESTRATION)
# ============================================================================

# EventBridge Rule: Image Verified → Trigger Pipeline
resource "aws_cloudwatch_event_rule" "image_verified" {
  name        = "${var.project_name}-image-verified"
  description = "Trigger SageMaker pipeline when image is verified"

  event_pattern = jsonencode({
    source      = ["custom.healthcare"]
    detail-type = ["Image Status Changed"]
    detail = {
      status = ["verified"]
    }
  })

  tags = {
    Name = "${var.project_name}-image-verified-rule"
  }
}

resource "aws_cloudwatch_event_target" "pipeline_trigger" {
  rule      = aws_cloudwatch_event_rule.image_verified.name
  target_id = "PipelineTrigger"
  arn       = aws_lambda_function.pipeline_trigger.arn
  role_arn  = aws_iam_role.eventbridge_role.arn

  input_transformer {
    input_paths = {
      image_id = "$.detail.image_id"
    }
    input_template = jsonencode({
      image_id = "<image_id>"
    })
  }
}

# ============================================================================
# SECTION 8: SAGEMAKER PIPELINE
# ============================================================================

# SageMaker Model Package Group
resource "aws_sagemaker_model_package_group" "main" {
  model_package_group_name = "${var.project_name}-pneumonia-detection"

  model_package_group_description = "Package group for pneumonia detection models"

  tags = {
    Name = "${var.project_name}-pneumonia-detection"
  }
}

# SageMaker Pipeline
resource "aws_sagemaker_pipeline" "main" {
  pipeline_name             = "${var.project_name}-training-pipeline"
  pipeline_definition       = base64encode(templatefile("${path.module}/pipeline_definition.json", {
    role_arn                = aws_iam_role.sagemaker_role.arn
    training_bucket         = aws_s3_bucket.training_data.id
    models_bucket           = aws_s3_bucket.models.id
    preprocessing_image_uri = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/healthcare-preprocessing:latest"
    training_image_uri      = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/healthcare-training:latest"
    evaluation_image_uri    = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/healthcare-evaluation:latest"
    inference_image_uri     = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/healthcare-inference:latest"
  }))
  pipeline_definition_s3_location = aws_s3_object.pipeline_definition.id
  role_arn                        = aws_iam_role.sagemaker_role.arn

  tags = {
    Name = "${var.project_name}-training-pipeline"
  }

  depends_on = [aws_s3_object.pipeline_definition]
}

# Store pipeline definition in S3
resource "aws_s3_object" "pipeline_definition" {
  bucket = aws_s3_bucket.models.id
  key    = "pipeline-definition/pipeline.json"
  source = "${path.module}/pipeline_definition.json"

  tags = {
    Name = "${var.project_name}-pipeline-definition"
  }
}

# ============================================================================
# SECTION 9: ECR (DOCKER REGISTRY)
# ============================================================================

# ECR repositories for SageMaker container images
resource "aws_ecr_repository" "preprocessing" {
  name                 = "${var.project_name}-preprocessing"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.healthcare_imaging.arn
  }

  tags = {
    Name = "${var.project_name}-preprocessing"
  }
}

resource "aws_ecr_repository" "training" {
  name                 = "${var.project_name}-training"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${var.project_name}-training"
  }
}

resource "aws_ecr_repository" "evaluation" {
  name                 = "${var.project_name}-evaluation"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${var.project_name}-evaluation"
  }
}

resource "aws_ecr_repository" "inference" {
  name                 = "${var.project_name}-inference"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${var.project_name}-inference"
  }
}

# ============================================================================
# SECTION 10: CLOUDWATCH (MONITORING)
# ============================================================================

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "lambda_ingestion" {
  name              = "/aws/lambda/image-ingestion"
  retention_in_days = 30

  tags = {
    Name = "lambda-ingestion-logs"
  }
}

resource "aws_cloudwatch_log_group" "lambda_pipeline" {
  name              = "/aws/lambda/pipeline-trigger"
  retention_in_days = 30

  tags = {
    Name = "lambda-pipeline-logs"
  }
}

resource "aws_cloudwatch_log_group" "sagemaker_processing" {
  name              = "/aws/sagemaker/ProcessingJobs/${var.project_name}-preprocessing"
  retention_in_days = 30

  tags = {
    Name = "sagemaker-preprocessing-logs"
  }
}

resource "aws_cloudwatch_log_group" "sagemaker_training" {
  name              = "/aws/sagemaker/TrainingJobs/${var.project_name}-training"
  retention_in_days = 30

  tags = {
    Name = "sagemaker-training-logs"
  }
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-overview"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/Lambda", "Invocations", { stat = "Sum", label = "Lambda Invocations" }],
            ["AWS/SageMaker", "ModelTrainingTime", { stat = "Average", label = "Training Time" }],
            ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", { stat = "Sum", label = "DynamoDB Writes" }]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Healthcare Imaging MLOps Overview"
        }
      }
    ]
  })
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.project_name}-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Alert when Lambda function errors exceed threshold"
  alarm_actions       = var.sns_topic_arn != "" ? [var.sns_topic_arn] : []

  dimensions = {
    FunctionName = aws_lambda_function.image_ingestion.function_name
  }
}

resource "aws_cloudwatch_metric_alarm" "sagemaker_failures" {
  alarm_name          = "${var.project_name}-sagemaker-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "TrainingJobsFailed"
  namespace           = "AWS/SageMaker"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Alert when SageMaker training jobs fail"
  alarm_actions       = var.sns_topic_arn != "" ? [var.sns_topic_arn] : []
}

# ============================================================================
# OUTPUTS
# ============================================================================

output "healthimaging_datastore_id" {
  description = "AWS HealthImaging Datastore ID"
  value       = aws_healthimaging_datastore.main.datastore_id
}

output "sagemaker_pipeline_name" {
  description = "SageMaker Pipeline Name"
  value       = aws_sagemaker_pipeline.main.pipeline_name
}

output "training_bucket" {
  description = "S3 Training Data Bucket"
  value       = aws_s3_bucket.training_data.id
}

output "models_bucket" {
  description = "S3 Models Bucket"
  value       = aws_s3_bucket.models.id
}

output "image_ingestion_lambda_name" {
  description = "Image Ingestion Lambda Function Name"
  value       = aws_lambda_function.image_ingestion.function_name
}

output "pipeline_trigger_lambda_name" {
  description = "Pipeline Trigger Lambda Function Name"
  value       = aws_lambda_function.pipeline_trigger.function_name
}

output "metadata_table_name" {
  description = "DynamoDB Metadata Table Name"
  value       = aws_dynamodb_table.image_metadata.name
}

output "metrics_table_name" {
  description = "DynamoDB Metrics Table Name"
  value       = aws_dynamodb_table.training_metrics.name
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.healthcare_imaging.id
}

output "private_subnet_ids" {
  description = "Private Subnet IDs"
  value       = aws_subnet.private[*].id
}

output "kms_key_id" {
  description = "KMS Key ID for encryption"
  value       = aws_kms_key.healthcare_imaging.id
}
