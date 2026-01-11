# ============================================================================
# FRONTEND API & LAMBDAS
# Healthcare Imaging MLOps Platform
# Main application frontend with embedded OHIF viewer
# ============================================================================

# ============================================================================
# FRONTEND STATIC WEBSITE HOSTING (S3 + CloudFront)
# ============================================================================

resource "aws_s3_bucket" "frontend" {
  bucket        = "${var.project_name}-${var.environment}-frontend-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = {
    Name = "${var.project_name}-${var.environment}-frontend"
  }
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  versioning_configuration {
    status = "Enabled"
  }
}

# ============================================================================
# CLOUDFRONT ORIGIN ACCESS CONTROL
# ============================================================================

resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${var.project_name}-${var.environment}-frontend-oac"
  description                       = "OAC for frontend S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ============================================================================
# CLOUDFRONT RESPONSE HEADERS POLICY - Security headers
# ============================================================================

resource "aws_cloudfront_response_headers_policy" "frontend" {
  name    = "${var.project_name}-${var.environment}-frontend-headers"
  comment = "Security headers for main frontend"

  security_headers_config {
    # Strict Transport Security
    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      preload                    = true
      override                   = true
    }

    # Content Type Options
    content_type_options {
      override = true
    }

    # XSS Protection
    xss_protection {
      mode_block = true
      protection = true
      override   = true
    }

    # Referrer Policy
    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }
  }
}

# ============================================================================
# CLOUDFRONT DISTRIBUTION
# ============================================================================

resource "aws_cloudfront_distribution" "frontend" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100"
  comment             = "${var.project_name} Frontend"

  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = "S3-${aws_s3_bucket.frontend.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.frontend.id}"

    response_headers_policy_id = aws_cloudfront_response_headers_policy.frontend.id

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
  }

  # Handle SPA routing
  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-frontend-cdn"
  }
}

# ============================================================================
# S3 BUCKET POLICY FOR CLOUDFRONT
# ============================================================================

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontServicePrincipal"
        Effect    = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.frontend.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.frontend.arn
          }
        }
      }
    ]
  })
}

# ============================================================================
# FRONTEND CONFIGURATION FILE
# ============================================================================

resource "local_file" "frontend_config" {
  content = <<-EOF
// ============================================================================
// Auto-generated by Terraform - Healthcare Imaging MLOps Platform
// ============================================================================

window.APP_CONFIG = {
    // Environment
    ENVIRONMENT: "${var.environment}",
    ENABLE_DEBUG: ${var.environment == "dev" ? "true" : "false"},
    
    // AWS Region
    AWS_REGION: "${var.aws_region}",
    
    // API Gateway endpoint (for pipeline trigger, etc.)
    API_ENDPOINT: "${aws_apigatewayv2_api.frontend_api.api_endpoint}",
    
    // S3 bucket for DICOM uploads
    S3_BUCKET: "${module.storage.training_data_bucket_id}",
    
    // HealthImaging configuration
    HEALTHIMAGING: {
        DATASTORE_ID: "${module.healthimaging.data_store_id}",
        REGION: "${var.aws_region}"
    },
    
    // Cognito configuration for OIDC authentication
    COGNITO: {
        REGION: "${var.aws_region}",
        USER_POOL_ID: "${module.cognito.user_pool_id}",
        CLIENT_ID: "${module.cognito.user_pool_client_id}",
        IDENTITY_POOL_ID: "${module.cognito.identity_pool_id}",
        DOMAIN: "${module.cognito.user_pool_domain}.auth.${var.aws_region}.amazoncognito.com",
        OAUTH: {
            SCOPE: ["email", "openid", "profile", "aws.cognito.signin.user.admin"],
            REDIRECT_SIGN_IN: "https://${aws_cloudfront_distribution.frontend.domain_name}/callback",
            REDIRECT_SIGN_OUT: "https://${aws_cloudfront_distribution.frontend.domain_name}/",
            RESPONSE_TYPE: "code"
        }
    },
    
    // OHIF Viewer configuration
    OHIF: {
        VIEWER_URL: "https://${aws_cloudfront_distribution.ohif_viewer.domain_name}",
        EMBED_MODE: true  // Use iframe embedding
    },
    
    // API routes
    ROUTES: {
        TRIGGER_PIPELINE: "/trigger-pipeline",
        LIST_IMAGE_SETS: "/list-image-sets",
        GET_IMAGE_SET_METADATA: "/get-image-set-metadata",
        GET_PRESIGNED_URL: "/get-presigned-url"
    }
};

console.log("Healthcare Imaging MLOps - Config Loaded:", window.APP_CONFIG);
EOF
  filename = "${path.module}/../frontend/config.js"
}

# ============================================================================
# UPLOAD FRONTEND FILES TO S3
# ============================================================================

resource "aws_s3_object" "frontend_index" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "index.html"
  source       = "${path.module}/../frontend/index.html"
  content_type = "text/html"
  etag         = filemd5("${path.module}/../frontend/index.html")
}

resource "aws_s3_object" "frontend_config" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "config.js"
  content      = local_file.frontend_config.content
  content_type = "application/javascript"

  depends_on = [local_file.frontend_config]
}

# HTJ2K Decoder - OpenJPH WASM files
resource "aws_s3_object" "openjph_js" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "static/js/openjphjs.js"
  source       = "${path.module}/../frontend/static/js/openjphjs.js"
  content_type = "application/javascript"
  etag         = filemd5("${path.module}/../frontend/static/js/openjphjs.js")
}

resource "aws_s3_object" "openjph_wasm" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "static/js/openjphjs.wasm"
  source       = "${path.module}/../frontend/static/js/openjphjs.wasm"
  content_type = "application/wasm"
  etag         = filemd5("${path.module}/../frontend/static/js/openjphjs.wasm")
}

resource "aws_s3_object" "htj2k_worker" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "static/js/htj2k-worker.js"
  source       = "${path.module}/../frontend/static/js/htj2k-worker.js"
  content_type = "application/javascript"
  etag         = filemd5("${path.module}/../frontend/static/js/htj2k-worker.js")
}

# ============================================================================
# IAM ROLE FOR FRONTEND LAMBDAS
# ============================================================================

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
          "s3:HeadObject"
        ]
        Resource = [
          module.storage.training_data_bucket_arn,
          "${module.storage.training_data_bucket_arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "medical-imaging:GetImageSet",
          "medical-imaging:GetImageFrame",
          "medical-imaging:GetImageSetMetadata",
          "medical-imaging:SearchImageSets",
          "medical-imaging:ListImageSetVersions"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = [
          module.security.s3_kms_key_arn,
          module.security.sagemaker_kms_key_arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# ============================================================================
# LAMBDA: List Image Sets
# ============================================================================

data "archive_file" "list_image_sets_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../python/src/lambda_handlers/list_image_sets"
  output_path = "${path.module}/lambda_zips/list_image_sets.zip"
}

resource "aws_lambda_function" "list_image_sets" {
  filename         = data.archive_file.list_image_sets_zip.output_path
  function_name    = "${var.project_name}-${var.environment}-list-image-sets"
  role             = aws_iam_role.frontend_lambda_role.arn
  handler          = "handler.lambda_handler"
  source_code_hash = data.archive_file.list_image_sets_zip.output_base64sha256
  runtime          = "python3.11"
  timeout          = 30
  memory_size      = 256
  
  environment {
    variables = {
      DATASTORE_ID = module.healthimaging.data_store_id
      AWS_REGION_NAME = var.aws_region
    }
  }
}

# ============================================================================
# LAMBDA: Get Image Set Metadata
# ============================================================================

data "archive_file" "get_image_set_metadata_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../python/src/lambda_handlers/get_image_set_metadata"
  output_path = "${path.module}/lambda_zips/get_image_set_metadata.zip"
}

resource "aws_lambda_function" "get_image_set_metadata" {
  filename         = data.archive_file.get_image_set_metadata_zip.output_path
  function_name    = "${var.project_name}-${var.environment}-get-image-set-metadata"
  role             = aws_iam_role.frontend_lambda_role.arn
  handler          = "handler.lambda_handler"
  source_code_hash = data.archive_file.get_image_set_metadata_zip.output_base64sha256
  runtime          = "python3.11"
  timeout          = 30
  memory_size      = 256
  
  environment {
    variables = {
      DATASTORE_ID = module.healthimaging.data_store_id
      AWS_REGION_NAME = var.aws_region
    }
  }
}

# ============================================================================
# API GATEWAY (HTTP API)
# ============================================================================

resource "aws_apigatewayv2_api" "frontend_api" {
  name          = "${var.project_name}-${var.environment}-api"
  protocol_type = "HTTP"
  cors_configuration {
    allow_origins = [
      "https://${aws_cloudfront_distribution.frontend.domain_name}",
      "https://${aws_cloudfront_distribution.ohif_viewer.domain_name}",
      "http://localhost:3000",
      "http://localhost:8080"
    ]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["*"]
    max_age       = 86400
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.frontend_api.id
  name        = "$default"
  auto_deploy = true
}

# ============================================================================
# API ROUTES
# ============================================================================

# Route: List Image Sets
resource "aws_apigatewayv2_integration" "list_image_sets" {
  api_id           = aws_apigatewayv2_api.frontend_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.list_image_sets.invoke_arn
}

resource "aws_apigatewayv2_route" "list_image_sets" {
  api_id    = aws_apigatewayv2_api.frontend_api.id
  route_key = "GET /list-image-sets"
  target    = "integrations/${aws_apigatewayv2_integration.list_image_sets.id}"
}

# Route: Get Image Set Metadata
resource "aws_apigatewayv2_integration" "get_image_set_metadata" {
  api_id           = aws_apigatewayv2_api.frontend_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.get_image_set_metadata.invoke_arn
}

resource "aws_apigatewayv2_route" "get_image_set_metadata" {
  api_id    = aws_apigatewayv2_api.frontend_api.id
  route_key = "GET /get-image-set-metadata"
  target    = "integrations/${aws_apigatewayv2_integration.get_image_set_metadata.id}"
}

# Route: Trigger Pipeline
resource "aws_apigatewayv2_integration" "trigger_pipeline" {
  api_id             = aws_apigatewayv2_api.frontend_api.id
  integration_type   = "AWS_PROXY"
  integration_method = "POST"
  integration_uri    = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/${module.lambda_functions.pipeline_trigger_function_arn}/invocations"
}

resource "aws_apigatewayv2_route" "trigger_pipeline" {
  api_id    = aws_apigatewayv2_api.frontend_api.id
  route_key = "POST /trigger-pipeline"
  target    = "integrations/${aws_apigatewayv2_integration.trigger_pipeline.id}"
}

# ============================================================================
# LAMBDA: Get Presigned URL (for DICOM uploads)
# ============================================================================

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
  memory_size      = 256
  
  environment {
    variables = {
      BUCKET_NAME     = module.storage.training_data_bucket_id
      S3_BUCKET_NAME  = module.storage.training_data_bucket_id
      AWS_REGION_NAME = var.aws_region
    }
  }
}

# Route: Get Presigned URL
resource "aws_apigatewayv2_integration" "get_presigned_url" {
  api_id           = aws_apigatewayv2_api.frontend_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.get_presigned_url.invoke_arn
}

resource "aws_apigatewayv2_route" "get_presigned_url" {
  api_id    = aws_apigatewayv2_api.frontend_api.id
  route_key = "GET /get-presigned-url"
  target    = "integrations/${aws_apigatewayv2_integration.get_presigned_url.id}"
}

resource "aws_lambda_permission" "api_gw_get_presigned_url" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_presigned_url.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.frontend_api.execution_arn}/*/*"
}

# ============================================================================
# LAMBDA PERMISSIONS FOR API GATEWAY
# ============================================================================

resource "aws_lambda_permission" "api_gw_list_image_sets" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.list_image_sets.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.frontend_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "api_gw_get_image_set_metadata" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_image_set_metadata.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.frontend_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "api_gw_trigger_pipeline" {
  statement_id  = "AllowExecutionFromAPIGatewayTrigger"
  action        = "lambda:InvokeFunction"
  function_name = module.lambda_functions.pipeline_trigger_function_arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.frontend_api.execution_arn}/*/*"
}

# ============================================================================
# OUTPUTS
# ============================================================================

output "api_gateway_endpoint" {
  description = "API Gateway endpoint"
  value       = aws_apigatewayv2_api.frontend_api.api_endpoint
}

output "frontend_url" {
  description = "CloudFront URL for the frontend application"
  value       = "https://${aws_cloudfront_distribution.frontend.domain_name}"
}

output "frontend_bucket" {
  description = "S3 bucket for frontend assets"
  value       = aws_s3_bucket.frontend.id
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID for cache invalidation"
  value       = aws_cloudfront_distribution.frontend.id
}
