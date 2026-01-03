# ============================================================================
# AMAZON SAGEMAKER MODULE
# Healthcare Imaging MLOps Platform
# ============================================================================

# ============================================================================
# SAGEMAKER EXECUTION ROLE
# ============================================================================

resource "aws_iam_role" "sagemaker_execution" {
  name = var.sagemaker_role_name

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

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "sagemaker_full_access" {
  role       = aws_iam_role.sagemaker_execution.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}

resource "aws_iam_role_policy" "sagemaker_s3_access" {
  name = "${var.name_prefix}-sagemaker-s3-policy"
  role = aws_iam_role.sagemaker_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.artifact_bucket}",
          "arn:aws:s3:::${var.artifact_bucket}/*",
          "arn:aws:s3:::${var.training_data_bucket}",
          "arn:aws:s3:::${var.training_data_bucket}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = var.kms_key_id
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      }
    ]
  })
}

# ============================================================================
# SAGEMAKER PIPELINE
# ============================================================================

resource "aws_sagemaker_pipeline" "training" {
  pipeline_name         = var.pipeline_name
  pipeline_display_name = var.pipeline_name
  role_arn              = aws_iam_role.sagemaker_execution.arn

  pipeline_definition = jsonencode({
    Version = "2020-12-01"
    Metadata = {}
    Parameters = [
      {
        Name = "InputDataUri"
        Type = "String"
        DefaultValue = "s3://${var.training_data_bucket}/input/"
      },
      {
        Name = "OutputModelUri"
        Type = "String"
        DefaultValue = "s3://${var.artifact_bucket}/models/"
      },
      {
        Name = "TrainingInstanceType"
        Type = "String"
        DefaultValue = var.training_instance_type
      },
      {
        Name = "ProcessingInstanceType"
        Type = "String"
        DefaultValue = var.processing_instance_type
      }
    ]
    PipelineExperimentConfig = {
      ExperimentName = "${var.name_prefix}-experiment"
      TrialName      = "${var.name_prefix}-trial"
    }
    Steps = [
      {
        Name = "Preprocessing"
        Type = "Processing"
        Arguments = {
          ProcessingResources = {
            ClusterConfig = {
              InstanceCount = 1
              InstanceType  = { "Get" = "Parameters.ProcessingInstanceType" }
              VolumeSizeInGB = 50
            }
          }
          AppSpecification = {
            ImageUri = var.processing_container_uri
          }
          ProcessingInputs = [
            {
              InputName = "input-data"
              S3Input = {
                S3Uri = { "Get" = "Parameters.InputDataUri" }
                LocalPath = "/opt/ml/processing/input"
                S3DataType = "S3Prefix"
                S3InputMode = "File"
              }
            }
          ]
          ProcessingOutputConfig = {
            Outputs = [
              {
                OutputName = "preprocessed-data"
                S3Output = {
                  S3Uri = "s3://${var.artifact_bucket}/preprocessed/"
                  LocalPath = "/opt/ml/processing/output"
                  S3UploadMode = "EndOfJob"
                }
              }
            ]
          }
          RoleArn = aws_iam_role.sagemaker_execution.arn
        }
      },
      {
        Name = "Training"
        Type = "Training"
        Arguments = {
          AlgorithmSpecification = {
            TrainingImage = var.training_container_uri
            TrainingInputMode = "File"
          }
          InputDataConfig = [
            {
              ChannelName = "training"
              DataSource = {
                S3DataSource = {
                  S3DataType = "S3Prefix"
                  S3Uri = "s3://${var.artifact_bucket}/preprocessed/"
                  S3DataDistributionType = "FullyReplicated"
                }
              }
            }
          ]
          OutputDataConfig = {
            S3OutputPath = { "Get" = "Parameters.OutputModelUri" }
          }
          ResourceConfig = {
            InstanceCount = 1
            InstanceType  = { "Get" = "Parameters.TrainingInstanceType" }
            VolumeSizeInGB = 100
          }
          StoppingCondition = {
            MaxRuntimeInSeconds = 86400
          }
          RoleArn = aws_iam_role.sagemaker_execution.arn
        }
        DependsOn = ["Preprocessing"]
      },
      {
        Name = "Evaluation"
        Type = "Processing"
        Arguments = {
          ProcessingResources = {
            ClusterConfig = {
              InstanceCount = 1
              InstanceType  = { "Get" = "Parameters.ProcessingInstanceType" }
              VolumeSizeInGB = 50
            }
          }
          AppSpecification = {
            ImageUri = var.processing_container_uri
          }
          ProcessingInputs = [
            {
              InputName = "model"
              S3Input = {
                S3Uri = { "Get" = "Parameters.OutputModelUri" }
                LocalPath = "/opt/ml/processing/model"
                S3DataType = "S3Prefix"
                S3InputMode = "File"
              }
            }
          ]
          ProcessingOutputConfig = {
            Outputs = [
              {
                OutputName = "evaluation"
                S3Output = {
                  S3Uri = "s3://${var.artifact_bucket}/evaluation/"
                  LocalPath = "/opt/ml/processing/evaluation"
                  S3UploadMode = "EndOfJob"
                }
              }
            ]
          }
          RoleArn = aws_iam_role.sagemaker_execution.arn
        }
        DependsOn = ["Training"]
      }
    ]
  })

  tags = var.tags
}

# ============================================================================
# MODEL PACKAGE GROUP (MODEL REGISTRY)
# ============================================================================

resource "aws_sagemaker_model_package_group" "main" {
  count = var.enable_model_registry ? 1 : 0

  model_package_group_name        = var.model_package_group_name
  model_package_group_description = "Model registry for ${var.name_prefix} pneumonia detection models"

  tags = var.tags
}

# ============================================================================
# SAGEMAKER DOMAIN (OPTIONAL)
# ============================================================================

resource "aws_sagemaker_domain" "main" {
  count = var.create_sagemaker_domain ? 1 : 0

  domain_name = "${var.name_prefix}-domain"
  auth_mode   = "IAM"
  vpc_id      = var.vpc_id
  subnet_ids  = var.subnet_ids

  default_user_settings {
    execution_role = aws_iam_role.sagemaker_execution.arn

    security_groups = var.security_group_ids
  }

  tags = var.tags
}
