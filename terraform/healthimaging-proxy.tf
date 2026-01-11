# ============================================================================
# HEALTHIMAGING CLOUDFRONT PROXY
# Low-latency proxy for HealthImaging API with caching
# Based on AWS samples: amazon-cloudfront-delivery
# ============================================================================

# ============================================================================
# LAMBDA@EDGE FOR CORS AND JWT VALIDATION (viewer-request)
# ============================================================================

# IAM Role for Lambda@Edge (must be in us-east-1 for CloudFront)
resource "aws_iam_role" "healthimaging_edge_role" {
  name = "${var.project_name}-${var.environment}-hi-edge-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = [
            "lambda.amazonaws.com",
            "edgelambda.amazonaws.com"
          ]
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "healthimaging_edge_policy" {
  name = "${var.project_name}-${var.environment}-hi-edge-policy"
  role = aws_iam_role.healthimaging_edge_role.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "medical-imaging:GetImageFrame",
          "medical-imaging:GetImageSetMetadata"
        ]
        Resource = "*"
      }
    ]
  })
}

# Lambda@Edge function for origin request (signs requests to HealthImaging)
data "archive_file" "healthimaging_signer_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda_edge/healthimaging_signer"
  output_path = "${path.module}/lambda_zips/healthimaging_signer.zip"
}

resource "aws_lambda_function" "healthimaging_signer" {
  filename         = data.archive_file.healthimaging_signer_zip.output_path
  function_name    = "${var.project_name}-${var.environment}-hi-signer"
  role             = aws_iam_role.healthimaging_edge_role.arn
  handler          = "index.handler"
  source_code_hash = data.archive_file.healthimaging_signer_zip.output_base64sha256
  runtime          = "nodejs18.x"
  timeout          = 30
  memory_size      = 128
  publish          = true  # Required for Lambda@Edge
  
  # Lambda@Edge must be in us-east-1
  provider = aws
}

# Lambda@Edge function for viewer request (CORS preflight handling)
data "archive_file" "healthimaging_cors_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda_edge/cors_handler"
  output_path = "${path.module}/lambda_zips/healthimaging_cors.zip"
}

resource "aws_lambda_function" "healthimaging_cors" {
  filename         = data.archive_file.healthimaging_cors_zip.output_path
  function_name    = "${var.project_name}-${var.environment}-hi-cors"
  role             = aws_iam_role.healthimaging_edge_role.arn
  handler          = "index.handler"
  source_code_hash = data.archive_file.healthimaging_cors_zip.output_base64sha256
  runtime          = "nodejs18.x"
  timeout          = 5
  memory_size      = 128
  publish          = true  # Required for Lambda@Edge
  
  provider = aws
}

# ============================================================================
# CLOUDFRONT DISTRIBUTION FOR HEALTHIMAGING
# ============================================================================

# Cache policy - cache by query string (imageFrameId)
resource "aws_cloudfront_cache_policy" "healthimaging" {
  name        = "${var.project_name}-${var.environment}-hi-cache"
  comment     = "Cache policy for HealthImaging frames"
  default_ttl = 86400    # 1 day
  max_ttl     = 31536000 # 1 year (frames are immutable)
  min_ttl     = 86400
  
  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }
    headers_config {
      header_behavior = "whitelist"
      headers {
        items = ["Authorization"]
      }
    }
    query_strings_config {
      query_string_behavior = "all"
    }
  }
}

# Origin request policy - forward necessary headers
resource "aws_cloudfront_origin_request_policy" "healthimaging" {
  name    = "${var.project_name}-${var.environment}-hi-origin"
  comment = "Origin request policy for HealthImaging"
  
  cookies_config {
    cookie_behavior = "none"
  }
  headers_config {
    header_behavior = "whitelist"
    headers {
      items = ["Origin", "Access-Control-Request-Headers", "Access-Control-Request-Method"]
    }
  }
  query_strings_config {
    query_string_behavior = "all"
  }
}

# Response headers policy for CORS
resource "aws_cloudfront_response_headers_policy" "healthimaging" {
  name    = "${var.project_name}-${var.environment}-hi-cors"
  comment = "CORS headers for HealthImaging proxy"
  
  cors_config {
    access_control_allow_credentials = false
    access_control_max_age_sec       = 86400
    origin_override                  = false  # Don't override Lambda@Edge CORS headers
    
    access_control_allow_headers {
      items = ["*"]
    }
    access_control_allow_methods {
      items = ["GET", "POST", "OPTIONS", "HEAD"]
    }
    access_control_allow_origins {
      items = ["*"]  # Allow all origins - Lambda@Edge validates
    }
    access_control_expose_headers {
      items = ["Content-Length", "Content-Type"]
    }
  }
}

# CloudFront distribution
resource "aws_cloudfront_distribution" "healthimaging_proxy" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "${var.project_name} HealthImaging Proxy"
  price_class     = "PriceClass_100"
  
  # Origin: HealthImaging runtime endpoint
  origin {
    domain_name = "runtime-medical-imaging.${var.aws_region}.amazonaws.com"
    origin_id   = "healthimaging"
    
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }
  
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "healthimaging"
    
    cache_policy_id            = aws_cloudfront_cache_policy.healthimaging.id
    origin_request_policy_id   = aws_cloudfront_origin_request_policy.healthimaging.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.healthimaging.id
    
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    
    # Lambda@Edge for CORS preflight (viewer-request)
    lambda_function_association {
      event_type   = "viewer-request"
      lambda_arn   = aws_lambda_function.healthimaging_cors.qualified_arn
      include_body = false
    }
    
    # Lambda@Edge for request signing (origin-request)
    lambda_function_association {
      event_type   = "origin-request"
      lambda_arn   = aws_lambda_function.healthimaging_signer.qualified_arn
      include_body = true
    }
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
    Name = "${var.project_name}-${var.environment}-hi-proxy"
  }
}

# ============================================================================
# OUTPUTS
# ============================================================================

output "healthimaging_proxy_url" {
  description = "CloudFront URL for HealthImaging proxy"
  value       = "https://${aws_cloudfront_distribution.healthimaging_proxy.domain_name}"
}

output "healthimaging_proxy_distribution_id" {
  description = "CloudFront distribution ID for HealthImaging proxy"
  value       = aws_cloudfront_distribution.healthimaging_proxy.id
}
