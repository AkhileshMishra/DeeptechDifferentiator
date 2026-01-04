# ============================================================================
# IAM POLICY FIXES (Module 3 Requirements)
# ============================================================================

# 1. HealthImaging Full Access Policy (Needed for Ingestion Lambda/SageMaker)
resource "aws_iam_policy" "healthimaging_access" {
  name        = "${var.project_name}-${var.environment}-healthimaging-policy"
  description = "Allow full access to HealthImaging Datastores for Imaging AI"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "medical-imaging:GetImageSet",
          "medical-imaging:GetImageSetMetadata",
          "medical-imaging:GetImageFrame",
          "medical-imaging:ListImageSets",
          "medical-imaging:SearchImageSets",
          "medical-imaging:StartDICOMImportJob", # Critical for ingestion
          "medical-imaging:GetDICOMImportJob"
        ]
        Resource = "*" # Scope this to your datastore ARN in production
      }
    ]
  })
}

# 2. SageMaker Pipeline Execution Policy (Needed for EventBridge Trigger)
resource "aws_iam_policy" "sagemaker_pipeline_execution" {
  name        = "${var.project_name}-${var.environment}-pipeline-execution-policy"
  description = "Allow EventBridge to start SageMaker Pipelines"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sagemaker:StartPipelineExecution",
          "sagemaker:DescribePipeline",
          "sagemaker:ListPipelineExecutions"
        ]
        Resource = "arn:aws:sagemaker:${var.aws_region}:${var.aws_account_id}:pipeline/*"
      }
    ]
  })
}

# 3. IAM PassRole Policy (Lambda needs to pass SageMaker execution role)
resource "aws_iam_policy" "lambda_pass_role" {
  name        = "${var.project_name}-${var.environment}-lambda-pass-role-policy"
  description = "Allow Lambda to pass SageMaker execution role when starting pipelines"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = "arn:aws:iam::${var.aws_account_id}:role/${var.project_name}-${var.environment}-*"
        Condition = {
          StringEquals = {
            "iam:PassedToService" = [
              "sagemaker.amazonaws.com",
              "lambda.amazonaws.com"
            ]
          }
        }
      }
    ]
  })
}

# ============================================================================
# POLICY ATTACHMENTS
# ============================================================================

# Attach HealthImaging policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_healthimaging" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.healthimaging_access.arn
}

# Attach SageMaker pipeline execution policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_pipeline_trigger" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.sagemaker_pipeline_execution.arn
}

# Attach PassRole policy to Lambda role
resource "aws_iam_role_policy_attachment" "lambda_pass_role" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_pass_role.arn
}

# ============================================================================
# EXISTING IAM ROLES (Legacy - to be migrated to modules)
# ============================================================================

# --- IAM Role for Step Functions ---
resource "aws_iam_role" "sfn_role" {
  name = "sfn-execution-role-${var.environment}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "states.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy" "sfn_policy" {
  role = aws_iam_role.sfn_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = ["lambda:InvokeFunction"],
        Resource = [
          "arn:aws:lambda:${var.aws_region}:${var.aws_account_id}:function:*"
        ]
      }
    ]
  })
}

# --- IAM Role for EventBridge ---
resource "aws_iam_role" "eventbridge_role" {
  name = "eventbridge-sfn-role-${var.environment}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "events.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy" "eventbridge_policy" {
  role = aws_iam_role.eventbridge_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = ["states:StartExecution"],
        Resource = ["arn:aws:states:${var.aws_region}:${var.aws_account_id}:stateMachine:*"]
      }
    ]
  })
}

# --- IAM Role for Lambdas (Shared for brevity, separate in prod) ---
resource "aws_iam_role" "lambda_role" {
  name = "lambda-execution-role-${var.environment}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  role = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = ["s3:GetObject", "s3:PutObject", "s3:ListBucket", "s3:HeadObject"],
        Resource = ["arn:aws:s3:::*"]
      },
      {
        Effect = "Allow",
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
        Resource = "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:*"
      }
    ]
  })
}
