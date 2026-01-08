# ============================================================================
# TERRAFORM MAIN CONFIGURATION
# Healthcare Imaging MLOps Platform
# ============================================================================

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.24.0"
    }
    # REQUIRED: Cloud Control provider for HealthImaging
    awscc = {
      source  = "hashicorp/awscc"
      version = ">= 1.0.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
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
    }
  }
}

# REQUIRED: Configuration for the awscc provider
provider "awscc" {
  region = var.aws_region
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

  healthimaging_config = {
    data_store_name = "${local.name_prefix}-imaging-store"
    kms_enabled     = true
  }

  sagemaker_config = {
    pipeline_name          = "${local.name_prefix}-pneumonia-pipeline"
    model_name             = "${local.name_prefix}-pneumonia-model"
    training_instance_type = var.sagemaker_training_instance
    notebook_instance_type = var.sagemaker_notebook_instance
  }

  s3_buckets = {
    training_data    = "${local.name_prefix}-training-data-${data.aws_caller_identity.current.account_id}"
    preprocessed     = "${local.name_prefix}-preprocessed-data-${data.aws_caller_identity.current.account_id}"
    model_artifacts  = "${local.name_prefix}-model-artifacts-${data.aws_caller_identity.current.account_id}"
    logs             = "${local.name_prefix}-logs-${data.aws_caller_identity.current.account_id}"
  }
}

# ============================================================================
# DATA SOURCES & ZIP ARCHIVES
# ============================================================================

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

data "archive_file" "image_ingestion" {
  type        = "zip"
  source_dir  = "${path.module}/../python/src/lambda_handlers/image_ingestion"
  output_path = "${path.module}/lambda_zips/image_ingestion.zip"
}

data "archive_file" "pipeline_trigger" {
  type        = "zip"
  source_dir  = "${path.module}/../python/src/lambda_handlers/pipeline_trigger"
  output_path = "${path.module}/lambda_zips/pipeline_trigger.zip"
}

data "archive_file" "model_evaluation" {
  type        = "zip"
  source_dir  = "${path.module}/../python/src/lambda_handlers/model_evaluation"
  output_path = "${path.module}/lambda_zips/model_evaluation.zip"
}

data "archive_file" "model_registry" {
  type        = "zip"
  source_dir  = "${path.module}/../python/src/lambda_handlers/model_registry"
  output_path = "${path.module}/lambda_zips/model_registry.zip"
}

# ============================================================================
# MODULES
# ============================================================================

module "networking" {
  source = "./modules/networking"

  name_prefix              = local.name_prefix
  vpc_cidr                 = var.vpc_cidr
  availability_zones       = slice(data.aws_availability_zones.available.names, 0, 2)
  enable_nat_gateway       = var.enable_nat_gateway
  enable_vpc_endpoints     = true
  enable_flow_logs         = true
  flow_logs_retention_days = var.flow_logs_retention_days

  tags = local.common_tags
}

module "security" {
  source = "./modules/security"

  name_prefix              = local.name_prefix
  create_kms_key_s3        = true
  create_kms_key_sagemaker = true
  create_kms_key_logs      = true
  enable_secrets_manager   = true
  secrets = {
    dicom_api_key = var.dicom_api_key
  }

  tags = local.common_tags
}

module "storage" {
  source = "./modules/storage"

  name_prefix                  = local.name_prefix
  s3_buckets                   = local.s3_buckets
  kms_key_id                   = module.security.s3_kms_key_id
  enable_versioning            = true
  training_data_retention_days = 90
  logs_retention_days          = 30
  allow_healthimaging_access   = true
  allow_sagemaker_access       = true
  vpc_id                       = module.networking.vpc_id
  image_ingestion_lambda_arn   = module.lambda_functions.image_ingestion_function_arn

  tags = local.common_tags
  depends_on = [module.lambda_functions]
}

module "healthimaging" {
  source = "./modules/healthimaging"

  name_prefix            = local.name_prefix
  data_store_name        = local.healthimaging_config.data_store_name
  kms_key_id             = module.security.sagemaker_kms_key_arn
  
  allowed_principals = [
    module.sagemaker.sagemaker_execution_role_arn,
    module.lambda_functions.image_ingestion_role_arn, 
  ]

  dicom_ingestion_bucket = module.storage.training_data_bucket_id
  enable_logging         = true
  log_group_name         = "/aws/healthimaging/${local.name_prefix}"

  tags = local.common_tags
  depends_on = [module.storage, module.security]
}

module "sagemaker" {
  source = "./modules/sagemaker"

  name_prefix              = local.name_prefix
  pipeline_name            = local.sagemaker_config.pipeline_name
  training_instance_type   = local.sagemaker_config.training_instance_type
  processing_instance_type = var.sagemaker_processing_instance
  sagemaker_role_name      = "${local.name_prefix}-sagemaker-role"
  subnet_ids               = module.networking.private_subnet_ids
  security_group_ids       = [module.networking.sagemaker_security_group_id]
  kms_key_id               = module.security.sagemaker_kms_key_arn
  artifact_bucket          = module.storage.model_artifacts_bucket_id
  training_data_bucket     = module.storage.training_data_bucket_id
  enable_model_registry    = true
  model_package_group_name = "${local.name_prefix}-model-registry"
  
  training_container_uri   = "${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${local.name_prefix}-training:latest"
  processing_container_uri = "${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${local.name_prefix}-processing:latest"

  tags = local.common_tags
  depends_on = [module.storage, module.security, module.networking, module.ecr]
}

module "ecr" {
  source = "./modules/ecr"

  name_prefix          = local.name_prefix
  repositories         = ["preprocessing", "training", "evaluation", "inference", "api"]
  image_scan_on_push   = true
  image_retention_days = 30

  tags = local.common_tags
}

module "lambda_functions" {
  source = "./modules/lambda"

  name_prefix = local.name_prefix

  subnet_ids         = module.networking.private_subnet_ids
  security_group_ids = [module.networking.lambda_security_group_id]
  kms_key_arn        = module.security.sagemaker_kms_key_arn

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

  healthimaging_datastore_id = module.healthimaging.data_store_id
  image_metadata_table       = module.dynamodb.image_metadata_table_name
  training_metrics_table     = module.dynamodb.training_metrics_table_name
  sagemaker_pipeline_arn     = module.sagemaker.pipeline_arn
  model_artifacts_bucket     = module.storage.model_artifacts_bucket_id
  model_package_group        = module.sagemaker.model_registry_name

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

module "dynamodb" {
  source = "./modules/dynamodb"
  name_prefix = local.name_prefix
  
  kms_key_arn                   = module.security.sagemaker_kms_key_arn
  enable_point_in_time_recovery = true
  enable_ttl                    = true
  
  tags = local.common_tags
}

module "eventbridge" {
  source = "./modules/eventbridge"

  name_prefix    = local.name_prefix
  event_bus_name = "${local.name_prefix}-imaging-events"

  rules = {
    image_verified = {
      description = "Trigger SageMaker pipeline when image is verified"
      pattern = {
        source      = ["imaging.mlops"]
        detail-type = ["ImageVerified"]
        detail      = {}
      }
      targets = [{
        arn      = module.lambda_functions.pipeline_trigger_function_arn
        role_arn = null
        input    = jsonencode({
          trigger      = "workshop"
          datastore_id = module.healthimaging.data_store_id
        })
      }]
    }

    model_training_complete = {
      description = "Run model evaluation when training completes"
      pattern = {
        source      = ["aws.sagemaker"]
        detail-type = ["SageMaker Training Job State Change"]
        detail      = { status = ["Completed"] }  # Keep as object
      }
      targets = [{ 
        arn      = module.lambda_functions.model_evaluation_function_arn 
        role_arn = null
        input    = null 
      }]
    }

    model_evaluation_passed = {
      description = "Register model when evaluation passes"
      pattern = {
        source      = ["imaging.mlops"]
        detail-type = ["ModelEvaluationPassed"]
        detail      = {}
      }
      targets = [{ 
        arn      = module.lambda_functions.model_registry_function_arn 
        role_arn = null
        input    = null
      }]
    }
  }

  tags = local.common_tags
  depends_on = [module.sagemaker, module.lambda_functions]
}


module "monitoring" {
  source = "./modules/monitoring"

  name_prefix = local.name_prefix
  aws_region  = var.aws_region

  training_data_bucket   = module.storage.training_data_bucket_id
  model_artifacts_bucket = module.storage.model_artifacts_bucket_id

  tags = local.common_tags
  depends_on = [module.healthimaging, module.sagemaker, module.lambda_functions]
}

# ============================================================================
# OUTPUTS
# ============================================================================

output "healthimaging_data_store_id" { value = module.healthimaging.data_store_id }
output "sagemaker_pipeline_arn" { value = module.sagemaker.pipeline_arn }
output "training_data_bucket" { value = module.storage.training_data_bucket_id }

output "dynamodb_metrics_table" {
  description = "DynamoDB Metrics Table Name"
  value       = module.dynamodb.training_metrics_table_name
}

output "deployment_info" {
  value = {
    project_name     = var.project_name
    environment      = var.environment
    region           = var.aws_region
    healthimaging_id = module.healthimaging.data_store_id
  }
}
