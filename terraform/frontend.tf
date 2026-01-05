# ============================================================================
# FRONTEND API & LAMBDAS
# Complements main-modules.tf by adding the API Gateway for the UI
# ============================================================================

# --- 1. IAM Role for Frontend Lambdas ---
# We create a specific role to avoid conflicts with module roles
resource "aws_iam_role" "frontend_lambda_role" {
  name = "${var.project_name}-${var.environment}-frontend-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "frontend_lambda_policy" {
  name = "${var.project_name}-${var.environment}-frontend-policy"
  role = aws_iam_role.frontend_lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "medical-imaging:GetImageSet",
          "medical-imaging:GetImageFrame",
          "medical-imaging:GetImageSetMetadata",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

# --- 2. Lambda: Get Presigned URL (For Streaming) ---
data "archive_file" "get_presigned_url_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../python/src/lambda_handlers/get_presigned_url"
  output_path = "${path.module}/lambda_zips/get_presigned_url.zip"
}

resource "aws_lambda_function" "get_presigned_url" {
  filename         = data.archive_file.get_presigned_url_zip.output_path
  function_name    = "${var.project_name}-${var.environment}-get-presigned-url"
  role             = aws_iam_role.frontend_lambda_role.arn
  handler          = "handler.lambda_handler"
  source_code_hash = data.archive_file.get_presigned_url_zip.output_base64sha256
  runtime          = "python3.11"
  timeout          = 30
  
  # Connects to the bucket created in main-modules.tf
  environment {
    variables = {
      BUCKET_NAME = module.storage.training_data_bucket_id
    }
  }
}

# --- 3. API Gateway (HTTP API) ---
resource "aws_apigatewayv2_api" "frontend_api" {
  name          = "${var.project_name}-${var.environment}-api"
  protocol_type = "HTTP"
  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["*"]
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.frontend_api.id
  name        = "$default"
  auto_deploy = true
}

# Route 1: Get Image Frame URL
resource "aws_apigatewayv2_integration" "get_url_int" {
  api_id           = aws_apigatewayv2_api.frontend_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.get_presigned_url.invoke_arn
}

resource "aws_apigatewayv2_route" "get_url_route" {
  api_id    = aws_apigatewayv2_api.frontend_api.id
  route_key = "GET /get-image-frame"
  target    = "integrations/${aws_apigatewayv2_integration.get_url_int.id}"
}

# Route 2: Trigger Pipeline (Connects to the Lambda from main-modules.tf)
resource "aws_apigatewayv2_integration" "trigger_int" {
  api_id           = aws_apigatewayv2_api.frontend_api.id
  integration_type = "AWS_PROXY"
  # References the pipeline lambda created in the modules
  integration_uri  = module.lambda_functions.pipeline_trigger_function_arn
}

resource "aws_apigatewayv2_route" "trigger_route" {
  api_id    = aws_apigatewayv2_api.frontend_api.id
  route_key = "POST /trigger-pipeline"
  target    = "integrations/${aws_apigatewayv2_integration.trigger_int.id}"
}

# --- 4. Permissions ---
resource "aws_lambda_permission" "api_gw_url" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_presigned_url.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.frontend_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "api_gw_trigger" {
  statement_id  = "AllowExecutionFromAPIGatewayTrigger"
  action        = "lambda:InvokeFunction"
  function_name = module.lambda_functions.pipeline_trigger_function_arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.frontend_api.execution_arn}/*/*"
}

# --- 5. Output ---
output "api_gateway_endpoint" {
  description = "The API Endpoint to use in frontend/config.js"
  value       = aws_apigatewayv2_api.frontend_api.api_endpoint
}
