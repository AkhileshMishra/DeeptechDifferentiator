# ============================================================================
# TERRAFORM MAIN CONFIGURATION
# Healthcare Imaging MLOps Platform
# ============================================================================

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      Owner       = var.owner_email
      # REMOVED: CreatedDate = timestamp() 
      # Reason: timestamp() forces an update on every 'terraform apply'
    }
  }
}

# ============================================================================
# LOCAL VARIABLES
# ============================================================================

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Module      = "HealthImaging-MLOps"
    CreatedBy   = "Terraform"
  }

  # HealthImaging configuration
  healthimaging_config = {
    data_store_name = "${local.name_prefix}-imaging-store"
    kms_enabled     = true
  }

  # SageMaker configuration
  sagemaker_config = {
    pipeline_name          = "${local.name_prefix}-pneumonia-pipeline"
    model_name             = "${local.name_prefix}-pneumonia-model"
    training_instance_type = var.sagemaker_training_instance
    notebook_instance_type = var.sagemaker_notebook_instance
  }

  # S3 buckets
  s3_buckets = {
    training_data    = "${local.name_prefix}-training-data-${data.aws_caller_identity.current.account_id}"
    preprocessed     = "${local.name_prefix}-preprocessed-data-${data.aws_caller_identity.current.account_id}"
    model_artifacts  = "${local.name_prefix}-model-artifacts-${data.aws_caller_identity.current.account_id}"
    logs             = "${local.name_prefix}-logs-${data.aws_caller_identity.current.account_id}"
  }
}

# ============================================================================
# DATA SOURCES
# ============================================================================

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

# ============================================================================
# VPC & NETWORKING
# ============================================================================

module "networking" {
  source = "./modules/networking"

  name_prefix             = local.name_prefix
  vpc_cidr                = var.vpc_cidr
  availability_zones      = slice(data.aws_availability_zones.available.names, 0, 2)
  enable_nat_gateway      = var.enable_nat_gateway
  enable_vpc_endpoints    = true
  enable_flow_logs        = true
  flow_logs_retention_days = var.flow_logs_retention_days

  tags = local.common_tags
}

# ============================================================================
# SECURITY & ENCRYPTION
# ============================================================================

module "security" {
  source = "./modules/security"

  name_prefix = local.name_prefix

  # KMS keys for encryption
  create_kms_key_s3        = true
  create_kms_key_sagemaker = true
  create_kms_key_logs      = true

  # Secrets
  enable_secrets_manager = true
  secrets = {
    dicom_api_key = var.dicom_api_key
  }

  tags = local.common_tags
}

# ============================================================================
# STORAGE LAYER
# ============================================================================

module "storage" {
  source = "./modules/storage"

  name_prefix   = local.name_prefix
  s3_buckets    = local.s3_buckets
  kms_key_id    = module.security.s3_kms_key_id
  enable_versioning = true
  
  # Lifecycle policies
  training_data_retention_days = 90
  logs_retention_days          = 30

  # Bucket policies
  allow_healthimaging_access = true
  allow_sagemaker_access     = true

  vpc_id = module.networking.vpc_id

  tags = local.common_tags
}

# ============================================================================
# AWS HEALTHIMAGING
# ============================================================================

module "healthimaging" {
  source = "./modules/healthimaging"

  name_prefix = local.name_prefix
  
  # Data store configuration
  data_store_name = local.healthimaging_config.data_store_name

  # Encryption
  kms_key_id = module.security.sagemaker_kms_key_id

  # Access configuration
  allowed_principals = [
    module.sagemaker.sagemaker_execution_role_arn,
    module.lambda_functions.image_ingestion_role_arn,
  ]

  # S3 integration
  dicom_ingestion_bucket = module.storage.training_data_bucket_id
  
  enable_logging = true
  log_group_name = "/aws/healthimaging/${local.name_prefix}"

  tags = local.common_tags

  depends_on = [
    module.storage,
    module.security
  ]
}

# ============================================================================
# AMAZON SAGEMAKER
# ============================================================================

module "sagemaker" {
  source = "./modules/sagemaker"

  name_prefix = local.name_prefix

  # Pipeline configuration
  pipeline_name = local.sagemaker_config.pipeline_name
  
  # Instance types
  training_instance_type = local.sagemaker_config.training_instance_type
  processing_instance_type = var.sagemaker_processing_instance

  # IAM
  sagemaker_role_name = "${local.name_prefix}-sagemaker-role"

  # VPC configuration
  subnet_ids         = module.networking.private_subnet_ids
  security_group_ids = [module.networking.sagemaker_security_group_id]

  # Encryption
  kms_key_id = module.security.sagemaker_kms_key_id

  # S3 artifacts
  artifact_bucket = module.storage.model_artifacts_bucket_id
  training_data_bucket = module.storage.training_data_bucket_id

  # Model registry
  enable_model_registry = true
  model_package_group_name = "${local.name_prefix}-model-registry"

  # Container images
  training_container_uri = "${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${local.name_prefix}-training:latest"
  processing_container_uri = "${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${local.name_prefix}-processing:latest"

  tags = local.common_tags

  depends_on = [
    module.storage,
    module.security,
    module.networking,
    module.ecr
  ]
}

# ============================================================================
# DOCKER CONTAINER REGISTRY (ECR)
# ============================================================================

module "ecr" {
  source = "./modules/ecr"

  name_prefix = local.name_prefix
  
  # Repository configuration
  repositories = [
    "preprocessing",
    "training",
    "evaluation",
    "inference",
    "api"
  ]

  # Image scanning
  image_scan_on_push = true

  # Retention policy
  image_retention_days = 30

  tags = local.common_tags
}

# ============================================================================
# EVENTBRIDGE & AUTOMATION
# ============================================================================

module "eventbridge" {
  source = "./modules/eventbridge"

  name_prefix = local.name_prefix

  # Event bus
  event_bus_name = "${local.name_prefix}-imaging-events"

  # Event rules for automation
  rules = {
    image_verified = {
      description = "Trigger SageMaker pipeline when image is verified (workshop deterministic)"
      pattern = {
        source      = ["imaging.mlops"]
        detail-type = ["ImageVerified"]
      }
      targets = [{
        arn = module.lambda_functions.pipeline_trigger_function_arn

        # Optional: pass a clean payload to Lambda for logging/parameter mapping.
        input = jsonencode({
          trigger = "workshop"
          datastore_id = module.healthimaging.data_store_id
        })
      }]
    }

    # Keep these ONLY if you have the Lambda code packaged and want the extra wow.
    model_training_complete = {
      description = "Run model evaluation when training completes"
      pattern = {
        source      = ["aws.sagemaker"]
        detail-type = ["SageMaker Training Job State Change"]
        detail = {
          status = ["Completed"]
        }
      }
      targets = [{
        arn = module.lambda_functions.model_evaluation_function_arn
      }]
    }

    model_evaluation_passed = {
      description = "Register model when evaluation passes"
      pattern = {
        source      = ["imaging.mlops"]
        detail-type = ["ModelEvaluationPassed"]
      }
      targets = [{
        arn = module.lambda_functions.model_registry_function_arn
      }]
    }

    # Strongly recommend disabling this for the workshop unless you add back a working
    # EventBridge->SNS invoke role (since you removed module.iam_roles).
    # alert_rule_violation = {
    #   description = "Send notification when metrics exceed threshold"
    #   pattern = {
    #     source      = ["aws.cloudwatch"]
    #     detail-type = ["CloudWatch Alarm State Change"]
    #   }
    #   targets = [{
    #     arn = var.sns_alert_topic_arn
    #   }]
    # }
  }

  tags = local.common_tags

  depends_on = [
    module.sagemaker,
    module.lambda_functions
  ]
}

# ============================================================================
# LAMBDA FUNCTIONS (CORRECTED)
# ============================================================================

module "lambda_functions" {
  source = "./modules/lambda"

  name_prefix = local.name_prefix

  # --- 1. Network & Security (REQUIRED) ---
  # These are now top-level arguments, not inside vpc_config
  subnet_ids         = module.networking.private_subnet_ids
  security_group_ids = [module.networking.lambda_security_group_id]
  kms_key_arn        = module.security.sagemaker_kms_key_arn

  # --- 2. Resource Permissions (REQUIRED) ---
  # The module uses these ARNs to generate least-privilege IAM policies
  s3_bucket_arns = [
    module.storage.training_data_bucket_arn,
    module.storage.preprocessed_data_bucket_arn,
    module.storage.model_artifacts_bucket_arn,
    module.storage.logs_bucket_arn
  ]
  
  dynamodb_table_arns = [
    module.dynamodb.image_metadata_table_arn,
    module.dynamodb.training_metrics_table_arn,
    module.dynamodb.pipeline_state_table_arn
  ]

  # --- 3. Environment Configuration (REQUIRED) ---
  # These values are injected into the Lambda environment variables
  healthimaging_datastore_id = module.healthimaging.datastore_id
  image_metadata_table       = module.dynamodb.image_metadata_table_name
  training_metrics_table     = module.dynamodb.training_metrics_table_name
  sagemaker_pipeline_arn     = module.sagemaker.pipeline_arn
  model_artifacts_bucket     = module.storage.model_artifacts_bucket_id
  model_package_group        = module.sagemaker.model_registry_name

  # --- 4. Function Definitions ---
  functions = {
    image_ingestion = {
      description = "Process uploaded DICOM images"
      handler     = "index.handler"
      runtime     = "python3.11"
      timeout     = 300
      memory_size = 512
      zip_file    = data.archive_file.image_ingestion.output_path
    }

    pipeline_trigger = {
      description = "Trigger SageMaker pipeline when image verified"
      handler     = "index.handler"
      runtime     = "python3.11"
      timeout     = 60
      memory_size = 256
      zip_file    = data.archive_file.pipeline_trigger.output_path
    }

    model_evaluation = {
      description = "Evaluate trained model against test dataset"
      handler     = "index.handler"
      runtime     = "python3.11"
      timeout     = 900
      memory_size = 1024
      zip_file    = data.archive_file.model_evaluation.output_path
    }

    model_registry = {
      description = "Register approved models in SageMaker Model Registry"
      handler     = "index.handler"
      runtime     = "python3.11"
      timeout     = 300
      memory_size = 512
      zip_file    = data.archive_file.model_registry.output_path
    }
  }

  tags = local.common_tags

  depends_on = [module.storage, module.sagemaker, module.networking, module.dynamodb]
}

# ============================================================================
# DYNAMODB (FIXED)
# ============================================================================

module "dynamodb" {
  source = "./modules/dynamodb"

  name_prefix = local.name_prefix

  # FIXED: The module requires "kms_key_arn", NOT "kms_key_id"
  kms_key_arn = module.security.sagemaker_kms_key_arn

  # FIXED: The module requires "enable_point_in_time_recovery", NOT "point_in_time_recovery"
  enable_point_in_time_recovery = true

  # FIXED: The module requires "enable_ttl", NOT "ttl_enabled"
  enable_ttl = true

  # REMOVED: The "tables" argument is not supported. 
  # The module automatically creates the required tables (image-metadata, training-metrics, etc.)
  
  tags = local.common_tags
}

# ============================================================================
# MONITORING & OBSERVABILITY
# ============================================================================

module "monitoring" {
  source = "./modules/monitoring"

  name_prefix = local.name_prefix

  # CloudWatch configuration
  log_retention_in_days = var.cloudwatch_retention_days

  # Dashboards
  dashboards = {
    healthimaging = {
      title = "${local.name_prefix}-HealthImaging-Dashboard"
      metrics = [
        "AWS/HealthImaging/RetrievalLatency",
        "AWS/HealthImaging/BytesTransferred",
        "AWS/HealthImaging/APICallCount"
      ]
    }

    sagemaker_pipeline = {
      title = "${local.name_prefix}-SageMaker-Pipeline-Dashboard"
      metrics = [
        "AWS/SageMaker/ModelTrainingTime",
        "AWS/SageMaker/TrainingJobCount",
        "AWS/SageMaker/ModelEvaluationScore"
      ]
    }

    mlops = {
      title = "${local.name_prefix}-MLOps-Dashboard"
      metrics = [
        "custom:PipelineExecutionTime",
        "custom:ModelAccuracy",
        "custom:DataValidationRate"
      ]
    }
  }

  # Alarms
  alarms = {
    healthimaging_latency = {
      metric_name         = "RetrievalLatency"
      namespace           = "AWS/HealthImaging"
      threshold           = 1000  # ms
      comparison_operator = "GreaterThanThreshold"
      alarm_actions       = [var.sns_alert_topic_arn]
    }

    sagemaker_training_failure = {
      metric_name         = "TrainingJobFailures"
      namespace           = "AWS/SageMaker"
      threshold           = 1
      comparison_operator = "GreaterThanOrEqualToThreshold"
      alarm_actions       = [var.sns_alert_topic_arn]
    }

    model_accuracy_degradation = {
      metric_name         = "ModelAccuracy"
      namespace           = "${local.name_prefix}/ModelMetrics"
      threshold           = 0.85  # 85% accuracy threshold
      comparison_operator = "LessThanThreshold"
      alarm_actions       = [var.sns_alert_topic_arn]
    }
  }

  tags = local.common_tags

  depends_on = [
    module.healthimaging,
    module.sagemaker,
    module.lambda_functions
  ]
}

# ============================================================================
# OUTPUTS
# ============================================================================

output "healthimaging_data_store_id" {
  description = "AWS HealthImaging Data Store ID"
  value       = module.healthimaging.data_store_id
}

output "sagemaker_pipeline_arn" {
  description = "SageMaker Pipeline ARN"
  value       = module.sagemaker.pipeline_arn
}

output "sagemaker_pipeline_name" {
  description = "SageMaker Pipeline Name"
  value       = module.sagemaker.pipeline_name
}

output "training_data_bucket" {
  description = "S3 bucket for training data"
  value       = module.storage.training_data_bucket_id
}

output "model_artifacts_bucket" {
  description = "S3 bucket for model artifacts"
  value       = module.storage.model_artifacts_bucket_id
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.networking.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.networking.private_subnet_ids
}

output "eventbridge_event_bus_arn" {
  description = "EventBridge Event Bus ARN"
  value       = module.eventbridge.event_bus_arn
}

output "lambda_image_ingestion_arn" {
  description = "Image Ingestion Lambda Function ARN"
  value       = module.lambda_functions.image_ingestion_function_arn
}

output "dynamodb_metrics_table" {
  description = "DynamoDB Metrics Table Name"
  value       = module.dynamodb.metrics_table_name
}

output "monitoring_dashboards" {
  description = "CloudWatch Dashboard URLs"
  value = {
    healthimaging = "https://console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${module.monitoring.healthimaging_dashboard_name}"
    sagemaker     = "https://console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${module.monitoring.sagemaker_dashboard_name}"
    mlops         = "https://console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${module.monitoring.mlops_dashboard_name}"
  }
}

output "deployment_info" {
  description = "Complete deployment information"
  value = {
    project_name     = var.project_name
    environment      = var.environment
    region           = var.aws_region
    account_id       = data.aws_caller_identity.current.account_id
    deployment_date  = timestamp()
    healthimaging_id = module.healthimaging.data_store_id
    pipeline_name    = module.sagemaker.pipeline_name
  }
}
