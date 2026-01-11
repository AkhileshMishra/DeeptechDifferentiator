# ============================================================================
# OHIF VIEWER INFRASTRUCTURE
# Healthcare Imaging MLOps Platform
# Hosts OHIF Viewer with HealthImaging adapter for HTJ2K streaming
# ============================================================================

# ============================================================================
# S3 BUCKET FOR OHIF VIEWER
# ============================================================================

resource "aws_s3_bucket" "ohif_viewer" {
  bucket        = "${var.project_name}-${var.environment}-ohif-viewer-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = {
    Name        = "${var.project_name}-${var.environment}-ohif-viewer"
    Purpose     = "OHIF Medical Imaging Viewer"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_public_access_block" "ohif_viewer" {
  bucket = aws_s3_bucket.ohif_viewer.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "ohif_viewer" {
  bucket = aws_s3_bucket.ohif_viewer.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ohif_viewer" {
  bucket = aws_s3_bucket.ohif_viewer.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ============================================================================
# CLOUDFRONT ORIGIN ACCESS CONTROL FOR OHIF
# ============================================================================

resource "aws_cloudfront_origin_access_control" "ohif_viewer" {
  name                              = "${var.project_name}-${var.environment}-ohif-oac"
  description                       = "OAC for OHIF Viewer S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ============================================================================
# CLOUDFRONT RESPONSE HEADERS POLICY - Allow iframe embedding
# ============================================================================

resource "aws_cloudfront_response_headers_policy" "ohif_viewer" {
  name    = "${var.project_name}-${var.environment}-ohif-headers"
  comment = "Headers policy for OHIF Viewer - allows iframe embedding"

  security_headers_config {
    # Allow framing from same origin and main app
    frame_options {
      frame_option = "SAMEORIGIN"
      override     = true
    }

    # Content Security Policy - allow framing
    content_security_policy {
      content_security_policy = "frame-ancestors 'self' https://${aws_cloudfront_distribution.frontend.domain_name}"
      override                = true
    }

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
  }

  # CORS headers for HealthImaging API calls
  cors_config {
    access_control_allow_credentials = false

    access_control_allow_headers {
      items = ["*"]
    }

    access_control_allow_methods {
      items = ["GET", "HEAD", "OPTIONS", "POST"]
    }

    access_control_allow_origins {
      items = [
        "https://${aws_cloudfront_distribution.frontend.domain_name}",
        "https://*.amazonaws.com"
      ]
    }

    access_control_max_age_sec = 86400
    origin_override            = true
  }
}

# ============================================================================
# CLOUDFRONT DISTRIBUTION FOR OHIF VIEWER
# ============================================================================

resource "aws_cloudfront_distribution" "ohif_viewer" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100"
  comment             = "${var.project_name} OHIF Viewer"

  origin {
    domain_name              = aws_s3_bucket.ohif_viewer.bucket_regional_domain_name
    origin_id                = "S3-${aws_s3_bucket.ohif_viewer.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.ohif_viewer.id
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.ohif_viewer.id}"

    # Use response headers policy for iframe embedding
    response_headers_policy_id = aws_cloudfront_response_headers_policy.ohif_viewer.id

    forwarded_values {
      query_string = true
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

  # Handle SPA routing - return index.html for 404s
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
    Name        = "${var.project_name}-${var.environment}-ohif-cdn"
    Purpose     = "OHIF Medical Imaging Viewer CDN"
    Environment = var.environment
  }
}

# ============================================================================
# S3 BUCKET POLICY FOR CLOUDFRONT
# ============================================================================

resource "aws_s3_bucket_policy" "ohif_viewer" {
  bucket = aws_s3_bucket.ohif_viewer.id

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
        Resource = "${aws_s3_bucket.ohif_viewer.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.ohif_viewer.arn
          }
        }
      }
    ]
  })
}

# ============================================================================
# OHIF CONFIGURATION FILE
# ============================================================================

resource "local_file" "ohif_config" {
  content = jsonencode({
    routerBasename = "/"
    
    # Data sources - AWS HealthImaging
    dataSources = [
      {
        namespace       = "@ohif/extension-default.dataSourcesModule.healthimaging"
        sourceName      = "healthimaging"
        configuration = {
          name        = "AWS HealthImaging"
          datastoreID = module.healthimaging.data_store_id
          region      = var.aws_region
          
          # Authentication via Cognito
          authConfig = {
            type                  = "cognito"
            region                = var.aws_region
            userPoolId            = module.cognito.user_pool_id
            userPoolWebClientId   = module.cognito.user_pool_client_id
            identityPoolId        = module.cognito.identity_pool_id
            oauth = {
              domain       = "${module.cognito.user_pool_domain}.auth.${var.aws_region}.amazoncognito.com"
              scope        = ["email", "openid", "profile", "aws.cognito.signin.user.admin"]
              redirectSignIn  = "https://${aws_cloudfront_distribution.ohif_viewer.domain_name}/callback"
              redirectSignOut = "https://${aws_cloudfront_distribution.ohif_viewer.domain_name}/"
              responseType = "code"
            }
          }
        }
      }
    ]
    
    defaultDataSourceName = "healthimaging"
    
    # Extensions
    extensions = []
    
    # Modes
    modes = []
    
    # Show study list
    showStudyList = true
    
    # Max number of web workers for decoding
    maxNumberOfWebWorkers = 4
    
    # Show warning message for cross-origin isolation
    showWarningMessageForCrossOrigin = false
    
    # Strict zoom/pan tool behavior
    strictZoomAndPan = false
    
    # Investigation UX
    investigationalUseDialog = {
      option = "never"
    }
  })
  
  filename = "${path.module}/../ohif/app-config.js"
}

# ============================================================================
# OHIF INDEX.HTML TEMPLATE
# ============================================================================

resource "local_file" "ohif_index" {
  content = <<-EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Medical Imaging Viewer - OHIF</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        html, body, #root { width: 100%; height: 100%; }
        body { 
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #000;
        }
        .loading {
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            height: 100vh;
            color: #fff;
        }
        .loading-spinner {
            width: 50px;
            height: 50px;
            border: 3px solid #333;
            border-top-color: #00d4ff;
            border-radius: 50%;
            animation: spin 1s linear infinite;
        }
        @keyframes spin {
            to { transform: rotate(360deg); }
        }
        .loading-text {
            margin-top: 20px;
            font-size: 14px;
            color: #888;
        }
    </style>
    
    <!-- OHIF Viewer will be loaded here -->
    <script>
        window.config = ${jsonencode({
          routerBasename = "/"
          dataSources = [
            {
              namespace     = "@ohif/extension-default.dataSourcesModule.healthimaging"
              sourceName    = "healthimaging"
              configuration = {
                name        = "AWS HealthImaging"
                datastoreID = module.healthimaging.data_store_id
                region      = var.aws_region
              }
            }
          ]
          defaultDataSourceName = "healthimaging"
        })};
        
        // Cognito configuration
        window.cognitoConfig = {
            region: "${var.aws_region}",
            userPoolId: "${module.cognito.user_pool_id}",
            userPoolWebClientId: "${module.cognito.user_pool_client_id}",
            identityPoolId: "${module.cognito.identity_pool_id}",
            oauth: {
                domain: "${module.cognito.user_pool_domain}.auth.${var.aws_region}.amazoncognito.com",
                scope: ["email", "openid", "profile", "aws.cognito.signin.user.admin"],
                redirectSignIn: "https://${aws_cloudfront_distribution.ohif_viewer.domain_name}/callback",
                redirectSignOut: "https://${aws_cloudfront_distribution.ohif_viewer.domain_name}/",
                responseType: "code"
            }
        };
        
        // HealthImaging configuration
        window.healthImagingConfig = {
            datastoreId: "${module.healthimaging.data_store_id}",
            region: "${var.aws_region}"
        };
    </script>
</head>
<body>
    <div id="root">
        <div class="loading">
            <div class="loading-spinner"></div>
            <div class="loading-text">Loading OHIF Viewer...</div>
        </div>
    </div>
    
    <!-- 
    NOTE: OHIF build files need to be deployed here.
    Run: npm run build in OHIF source, then copy dist/* to this S3 bucket.
    See ohif/README.md for build instructions.
    -->
</body>
</html>
EOF
  
  filename = "${path.module}/../ohif/index.html"
}

# ============================================================================
# UPLOAD OHIF FILES TO S3
# ============================================================================

resource "aws_s3_object" "ohif_index" {
  bucket       = aws_s3_bucket.ohif_viewer.id
  key          = "index.html"
  content      = local_file.ohif_index.content
  content_type = "text/html"

  depends_on = [local_file.ohif_index]
}

resource "aws_s3_object" "ohif_config" {
  bucket       = aws_s3_bucket.ohif_viewer.id
  key          = "app-config.js"
  content      = local_file.ohif_config.content
  content_type = "application/javascript"

  depends_on = [local_file.ohif_config]
}

# ============================================================================
# OUTPUTS
# ============================================================================

output "ohif_viewer_url" {
  description = "URL for the OHIF Viewer"
  value       = "https://${aws_cloudfront_distribution.ohif_viewer.domain_name}"
}

output "ohif_viewer_bucket" {
  description = "S3 bucket for OHIF Viewer assets"
  value       = aws_s3_bucket.ohif_viewer.id
}

output "ohif_cloudfront_distribution_id" {
  description = "CloudFront distribution ID for OHIF Viewer"
  value       = aws_cloudfront_distribution.ohif_viewer.id
}
