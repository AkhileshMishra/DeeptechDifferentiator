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
