# ============================================================================
# COGNITO MODULE
# Healthcare Imaging MLOps Platform - OIDC Authentication for HealthImaging
# Implements AWS Reference Architecture for OHIF + HealthImaging
# ============================================================================

# ============================================================================
# COGNITO USER POOL
# ============================================================================

resource "aws_cognito_user_pool" "main" {
  name = "${var.name_prefix}-user-pool"

  # Password policy
  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = false
    require_uppercase = true
  }

  # Auto-verify email
  auto_verified_attributes = ["email"]

  # Account recovery
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # Schema
  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true

    string_attribute_constraints {
      min_length = 1
      max_length = 256
    }
  }

  tags = var.tags
}

# ============================================================================
# COGNITO USER POOL CLIENT - For OHIF Viewer (OIDC)
# ============================================================================

resource "aws_cognito_user_pool_client" "main" {
  name         = "${var.name_prefix}-app-client"
  user_pool_id = aws_cognito_user_pool.main.id

  # No client secret for browser-based apps (SPA)
  generate_secret = false

  # OAuth settings - Authorization Code Grant for OIDC
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["email", "openid", "profile", "aws.cognito.signin.user.admin"]
  allowed_oauth_flows_user_pool_client = true
  
  callback_urls = var.callback_urls
  logout_urls   = var.logout_urls

  # Token validity
  access_token_validity  = 1  # hours
  id_token_validity      = 1  # hours
  refresh_token_validity = 30 # days

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  # Explicit auth flows for browser + refresh
  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_PASSWORD_AUTH"
  ]

  supported_identity_providers = ["COGNITO"]
  
  # Enable token revocation
  enable_token_revocation = true
  
  # Prevent user existence errors
  prevent_user_existence_errors = "ENABLED"
}

# ============================================================================
# COGNITO USER POOL DOMAIN
# ============================================================================

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.name_prefix}-${var.aws_account_id}"
  user_pool_id = aws_cognito_user_pool.main.id
}

# ============================================================================
# COGNITO IDENTITY POOL - For AWS Credentials Exchange
# ============================================================================

resource "aws_cognito_identity_pool" "main" {
  identity_pool_name               = "${var.name_prefix}-identity-pool"
  allow_unauthenticated_identities = false  # Production: require authentication
  allow_classic_flow               = false

  cognito_identity_providers {
    client_id               = aws_cognito_user_pool_client.main.id
    provider_name           = aws_cognito_user_pool.main.endpoint
    server_side_token_check = true
  }

  tags = var.tags
}

# ============================================================================
# IAM ROLES FOR IDENTITY POOL - HealthImaging Access
# ============================================================================

# Authenticated role - for logged-in users accessing HealthImaging
resource "aws_iam_role" "authenticated" {
  name = "${var.name_prefix}-cognito-authenticated"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "cognito-identity.amazonaws.com"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "cognito-identity.amazonaws.com:aud" = aws_cognito_identity_pool.main.id
          }
          "ForAnyValue:StringLike" = {
            "cognito-identity.amazonaws.com:amr" = "authenticated"
          }
        }
      }
    ]
  })

  tags = var.tags
}

# HealthImaging read access policy for authenticated users
resource "aws_iam_role_policy" "authenticated_healthimaging" {
  name = "${var.name_prefix}-cognito-healthimaging-policy"
  role = aws_iam_role.authenticated.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "HealthImagingReadAccess"
        Effect = "Allow"
        Action = [
          "medical-imaging:GetImageSet",
          "medical-imaging:GetImageFrame",
          "medical-imaging:GetImageSetMetadata",
          "medical-imaging:SearchImageSets",
          "medical-imaging:ListImageSetVersions",
          "medical-imaging:GetDICOMImportJob",
          "medical-imaging:ListDICOMImportJobs"
        ]
        Resource = [
          var.healthimaging_datastore_arn,
          "${var.healthimaging_datastore_arn}/*"
        ]
      },
      {
        Sid    = "HealthImagingListDatastores"
        Effect = "Allow"
        Action = [
          "medical-imaging:ListDatastores"
        ]
        Resource = "*"
      },
      {
        Sid    = "KMSDecryptForHealthImaging"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = var.kms_key_arn
        Condition = {
          StringEquals = {
            "kms:ViaService" = "medical-imaging.${var.aws_region}.amazonaws.com"
          }
        }
      }
    ]
  })
}

# S3 access for DICOM uploads (authenticated users can upload)
resource "aws_iam_role_policy" "authenticated_s3" {
  name = "${var.name_prefix}-cognito-s3-policy"
  role = aws_iam_role.authenticated.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3UploadAccess"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          var.dicom_upload_bucket_arn,
          "${var.dicom_upload_bucket_arn}/*"
        ]
      }
    ]
  })
}

# ============================================================================
# IDENTITY POOL ROLE ATTACHMENT
# ============================================================================

resource "aws_cognito_identity_pool_roles_attachment" "main" {
  identity_pool_id = aws_cognito_identity_pool.main.id

  roles = {
    "authenticated" = aws_iam_role.authenticated.arn
  }
}

# ============================================================================
# COGNITO USER POOL RESOURCE SERVER (Optional - for custom scopes)
# ============================================================================

resource "aws_cognito_resource_server" "healthimaging" {
  identifier   = "healthimaging"
  name         = "HealthImaging API"
  user_pool_id = aws_cognito_user_pool.main.id

  scope {
    scope_name        = "read"
    scope_description = "Read access to HealthImaging data"
  }

  scope {
    scope_name        = "write"
    scope_description = "Write access to HealthImaging data"
  }
}
