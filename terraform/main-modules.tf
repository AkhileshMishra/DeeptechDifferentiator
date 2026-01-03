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

  backend "s3" {
    # Configure these values via environment or backend config file
    # bucket         = "your-terraform-state-bucket"
    # key            = "healthcare-imaging/terraform.tfstate"
    # region         = "us-east-1"
    # encrypt        = true
    # dynamodb_table = "terraform-lock"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project             = var.project_name
      Environment         = var.environment
      ManagedByTerraform  = "true"
      CreatedDate         = timestamp()
      Owner               = var.owner_email
      CostCenter          = var.cost_center
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
      description = "Trigger SageMaker pipeline when image is verified"
      pattern = {
        source      = ["aws.healthimaging"]
        detail-type = ["HealthImaging ImageVerified"]
      }
      targets = [{
        arn = module.sagemaker.pipeline_arn
        role_arn = module.iam_roles.eventbridge_invoke_role_arn
      }]
    }

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
        role_arn = module.iam_roles.eventbridge_invoke_role_arn
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
        role_arn = module.iam_roles.eventbridge_invoke_role_arn
      }]
    }

    alert_rule_violation = {
      description = "Send notification when metrics exceed threshold"
      pattern = {
        source      = ["aws.cloudwatch"]
        detail-type = ["CloudWatch Alarm State Change"]
      }
      targets = [{
        arn = var.sns_alert_topic_arn
        role_arn = module.iam_roles.eventbridge_invoke_role_arn
      }]
    }
  }

  tags = local.common_tags

  depends_on = [
    module.sagemaker,
    module.lambda_functions
  ]
}

# ============================================================================
# LAMBDA FUNCTIONS
# ============================================================================

module "lambda_functions" {
  source = "./modules/lambda"

  name_prefix = local.name_prefix

  # Function definitions
  functions = {
    image_ingestion = {
      description = "Process uploaded DICOM images"
      handler     = "index.handler"
      timeout     = 300
      memory_size = 512
      environment = {
        HEALTHIMAGING_DATASTORE_ID = module.healthimaging.data_store_id
        TRAINING_BUCKET            = module.storage.training_data_bucket_id
        SAGEMAKER_PIPELINE_ARN     = module.sagemaker.pipeline_arn
      }
    }

    pipeline_trigger = {
      description = "Trigger SageMaker pipeline when image verified"
      handler     = "index.handler"
      timeout     = 60
      memory_size = 256
      environment = {
        SAGEMAKER_PIPELINE_ARN = module.sagemaker.pipeline_arn
      }
    }

    model_evaluation = {
      description = "Evaluate trained model against test dataset"
      handler     = "index.handler"
      timeout     = 900
      memory_size = 1024
      environment = {
        MODEL_BUCKET        = module.storage.model_artifacts_bucket_id
        METRICS_TABLE       = module.dynamodb.metrics_table_name
        CLOUDWATCH_NAMESPACE = "${local.name_prefix}/ModelMetrics"
      }
    }

    model_registry = {
      description = "Register approved models in SageMaker Model Registry"
      handler     = "index.handler"
      timeout     = 300
      memory_size = 512
      environment = {
        SAGEMAKER_ROLE_ARN = module.sagemaker.sagemaker_execution_role_arn
        MODEL_PACKAGE_GROUP = module.sagemaker.model_package_group_name
      }
    }
  }

  # VPC configuration
  vpc_config = {
    subnet_ids         = module.networking.private_subnet_ids
    security_group_ids = [module.networking.lambda_security_group_id]
  }

  # IAM permissions
  iam_policy_statements = [
    {
      actions   = ["healthimaging:*"]
      resources = ["*"]
    },
    {
      actions   = ["s3:*"]
      resources = [module.storage.training_data_bucket_arn, "${module.storage.training_data_bucket_arn}/*"]
    },
    {
      actions   = ["sagemaker:*"]
      resources = ["*"]
    }
  ]

  tags = local.common_tags

  depends_on = [
    module.storage,
    module.sagemaker,
    module.networking
  ]
}

# ============================================================================
# DYNAMODB (FOR METRICS & STATE)
# ============================================================================

module "dynamodb" {
  source = "./modules/dynamodb"

  name_prefix = local.name_prefix

  # Tables
  tables = {
    metrics = {
      table_name     = "${local.name_prefix}-model-metrics"
      billing_mode   = "PAY_PER_REQUEST"
      hash_key       = "model_version"
      range_key      = "evaluation_timestamp"
    }

    image_tracking = {
      table_name     = "${local.name_prefix}-image-tracking"
      billing_mode   = "PAY_PER_REQUEST"
      hash_key       = "image_id"
      range_key      = "ingestion_timestamp"
    }
  }

  # Backup & retention
  point_in_time_recovery = true
  ttl_enabled            = true

  # Encryption
  kms_key_id = module.security.sagemaker_kms_key_id

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
# IAM ROLES & POLICIES
# ============================================================================

module "iam_roles" {
  source = "./modules/iam"

  name_prefix = local.name_prefix

  # Define cross-service permissions
  service_permissions = {
    eventbridge_invoke = {
      services = ["sagemaker", "lambda", "sns"]
    }
    healthimaging_to_sagemaker = {
      source_service = "healthimaging"
      target_service = "sagemaker"
    }
  }

  tags = local.common_tags
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
