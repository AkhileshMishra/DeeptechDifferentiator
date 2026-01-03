# ============================================================================
# LAMBDA MODULE
# Healthcare Imaging MLOps Platform
# ============================================================================

# ============================================================================
# LAMBDA EXECUTION ROLE
# ============================================================================

resource "aws_iam_role" "lambda_execution" {
  name = "${var.name_prefix}-lambda-execution-role"

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

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role       = aws_iam_role.lambda_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "lambda_custom" {
  name = "${var.name_prefix}-lambda-custom-policy"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = var.s3_bucket_arns
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = var.dynamodb_table_arns
      },
      {
        Effect = "Allow"
        Action = [
          "sagemaker:StartPipelineExecution",
          "sagemaker:DescribePipelineExecution"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "medical-imaging:*"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = var.kms_key_arn
      }
    ]
  })
}

# ============================================================================
# IMAGE INGESTION LAMBDA
# ============================================================================

resource "aws_lambda_function" "image_ingestion" {
  function_name = "${var.name_prefix}-image-ingestion"
  role          = aws_iam_role.lambda_execution.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 300
  memory_size   = 1024

  filename         = var.functions.image_ingestion.zip_file
  source_code_hash = filebase64sha256(var.functions.image_ingestion.zip_file)

  environment {
    variables = {
      HEALTHIMAGING_DATASTORE_ID = var.healthimaging_datastore_id
      DYNAMODB_TABLE             = var.image_metadata_table
      LOG_LEVEL                  = "INFO"
    }
  }

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = var.security_group_ids
  }

  tags = var.tags
}

# ============================================================================
# PIPELINE TRIGGER LAMBDA
# ============================================================================

resource "aws_lambda_function" "pipeline_trigger" {
  function_name = "${var.name_prefix}-pipeline-trigger"
  role          = aws_iam_role.lambda_execution.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 60
  memory_size   = 256

  filename         = var.functions.pipeline_trigger.zip_file
  source_code_hash = filebase64sha256(var.functions.pipeline_trigger.zip_file)

  environment {
    variables = {
      SAGEMAKER_PIPELINE_ARN = var.sagemaker_pipeline_arn
      LOG_LEVEL              = "INFO"
    }
  }

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = var.security_group_ids
  }

  tags = var.tags
}

# ============================================================================
# MODEL EVALUATION LAMBDA
# ============================================================================

resource "aws_lambda_function" "model_evaluation" {
  function_name = "${var.name_prefix}-model-evaluation"
  role          = aws_iam_role.lambda_execution.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 300
  memory_size   = 512

  filename         = var.functions.model_evaluation.zip_file
  source_code_hash = filebase64sha256(var.functions.model_evaluation.zip_file)

  environment {
    variables = {
      MODEL_ARTIFACTS_BUCKET = var.model_artifacts_bucket
      METRICS_TABLE          = var.training_metrics_table
      ACCURACY_THRESHOLD     = "0.85"
      LOG_LEVEL              = "INFO"
    }
  }

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = var.security_group_ids
  }

  tags = var.tags
}

# ============================================================================
# MODEL REGISTRY LAMBDA
# ============================================================================

resource "aws_lambda_function" "model_registry" {
  function_name = "${var.name_prefix}-model-registry"
  role          = aws_iam_role.lambda_execution.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 120
  memory_size   = 256

  filename         = var.functions.model_registry.zip_file
  source_code_hash = filebase64sha256(var.functions.model_registry.zip_file)

  environment {
    variables = {
      MODEL_PACKAGE_GROUP = var.model_package_group
      LOG_LEVEL           = "INFO"
    }
  }

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = var.security_group_ids
  }

  tags = var.tags
}

# ============================================================================
# CLOUDWATCH LOG GROUPS
# ============================================================================

resource "aws_cloudwatch_log_group" "image_ingestion" {
  name              = "/aws/lambda/${aws_lambda_function.image_ingestion.function_name}"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "pipeline_trigger" {
  name              = "/aws/lambda/${aws_lambda_function.pipeline_trigger.function_name}"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "model_evaluation" {
  name              = "/aws/lambda/${aws_lambda_function.model_evaluation.function_name}"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "model_registry" {
  name              = "/aws/lambda/${aws_lambda_function.model_registry.function_name}"
  retention_in_days = var.log_retention_days

  tags = var.tags
}
