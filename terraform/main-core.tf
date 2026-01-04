terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    awscc = {
      source  = "hashicorp/awscc"
      version = "~> 1.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

provider "awscc" {
  region = var.aws_region
}

# --- 1. S3 Data Lake ---
resource "aws_s3_bucket" "data_lake" {
  bucket        = "healthtech-ingest-${var.env}-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

# --- 2. Lambda Functions (FIXED PATHS) ---

# Common Role for Lambdas
resource "aws_iam_role" "lambda_role" {
  name = "healthtech-lambda-role-${var.env}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "healthtech-lambda-policy-${var.env}"
  role = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:*",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "sagemaker:StartPipelineExecution",
          "medical-imaging:*"
        ]
        Resource = "*"
      }
    ]
  })
}

# MIME Extractor
data "archive_file" "mime_extractor_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../python/src/lambda_handlers/mime_extractor"
  output_path = "${path.module}/lambda_zips/mime_extractor.zip"
}

resource "aws_lambda_function" "mime_extractor" {
  filename         = data.archive_file.mime_extractor_zip.output_path
  function_name    = "mime-extractor-${var.env}"
  role             = aws_iam_role.lambda_role.arn
  handler          = "handler.lambda_handler"
  source_code_hash = data.archive_file.mime_extractor_zip.output_base64sha256
  runtime          = "python3.11"
  timeout          = 60
}

# Get Presigned URL / Image Frame
data "archive_file" "get_presigned_url_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../python/src/lambda_handlers/get_presigned_url"
  output_path = "${path.module}/lambda_zips/get_presigned_url.zip"
}

resource "aws_lambda_function" "get_presigned_url" {
  filename         = data.archive_file.get_presigned_url_zip.output_path
  function_name    = "get-presigned-url-${var.env}"
  role             = aws_iam_role.lambda_role.arn
  handler          = "handler.lambda_handler"
  source_code_hash = data.archive_file.get_presigned_url_zip.output_base64sha256
  runtime          = "python3.11"
  timeout          = 30
  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.data_lake.id
    }
  }
}

# Pipeline Trigger (Gap 3 Fix)
data "archive_file" "pipeline_trigger_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../python/src/lambda_handlers/pipeline_trigger"
  output_path = "${path.module}/lambda_zips/pipeline_trigger.zip"
}

resource "aws_lambda_function" "pipeline_trigger" {
  filename         = data.archive_file.pipeline_trigger_zip.output_path
  function_name    = "pipeline-trigger-${var.env}"
  role             = aws_iam_role.lambda_role.arn
  handler          = "handler.lambda_handler"
  source_code_hash = data.archive_file.pipeline_trigger_zip.output_base64sha256
  runtime          = "python3.11"
  timeout          = 60
  environment {
    variables = {
      PIPELINE_NAME = "HealthTechPipeline-${var.env}"
      S3_BUCKET     = aws_s3_bucket.data_lake.id
    }
  }
}

# --- 3. API Gateway (FIXED ROUTES) ---
resource "aws_apigatewayv2_api" "http_api" {
  name          = "healthtech-api-${var.env}"
  protocol_type = "HTTP"
  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["*"]
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true
}

# Route 1: Get URL / Image Frame
resource "aws_apigatewayv2_integration" "get_url_int" {
  api_id           = aws_apigatewayv2_api.http_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.get_presigned_url.invoke_arn
}

resource "aws_apigatewayv2_route" "get_url_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "GET /get-image-frame"
  target    = "integrations/${aws_apigatewayv2_integration.get_url_int.id}"
}

# Route 2: Trigger Pipeline (Gap 3 Fix)
resource "aws_apigatewayv2_integration" "trigger_int" {
  api_id           = aws_apigatewayv2_api.http_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.pipeline_trigger.invoke_arn
}

resource "aws_apigatewayv2_route" "trigger_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "POST /trigger-pipeline"
  target    = "integrations/${aws_apigatewayv2_integration.trigger_int.id}"
}

# Permissions
resource "aws_lambda_permission" "api_gw_url" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_presigned_url.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "api_gw_trigger" {
  statement_id  = "AllowExecutionFromAPIGatewayTrigger"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.pipeline_trigger.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

output "api_endpoint" {
  value = aws_apigatewayv2_api.http_api.api_endpoint
}
