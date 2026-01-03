# ============================================================================
# TERRAFORM VARIABLES
# Healthcare Imaging MLOps Platform
# ============================================================================

# ============================================================================
# CORE CONFIGURATION
# ============================================================================

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-\\d{1}$", var.aws_region))
    error_message = "Must be a valid AWS region format (e.g., us-east-1)"
  }
}

variable "aws_account_id" {
  description = "AWS Account ID (for ECR repositories)"
  type        = string

  validation {
    condition     = can(regex("^\\d{12}$", var.aws_account_id))
    error_message = "Must be a valid 12-digit AWS Account ID"
  }
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "healthcare-imaging"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,30}$", var.project_name))
    error_message = "Must start with lowercase letter and contain only lowercase letters, numbers, and hyphens"
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Must be one of: dev, staging, prod"
  }
}

variable "owner_email" {
  description = "Owner email for tagging and notifications"
  type        = string
}

variable "cost_center" {
  description = "Cost center for billing allocation"
  type        = string
  default     = "engineering"
}

# ============================================================================
# NETWORKING
# ============================================================================

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "Must be a valid CIDR block"
  }
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnets"
  type        = bool
  default     = true
}

variable "flow_logs_retention_days" {
  description = "VPC Flow Logs retention period in days"
  type        = number
  default     = 7

  validation {
    condition     = var.flow_logs_retention_days > 0
    error_message = "Must be greater than 0"
  }
}

# ============================================================================
# SECURITY
# ============================================================================

variable "dicom_api_key" {
  description = "API key for DICOM services (store in AWS Secrets Manager)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "enable_vpc_endpoints" {
  description = "Enable VPC endpoints for AWS services"
  type        = bool
  default     = true
}

variable "enable_encryption" {
  description = "Enable encryption at rest for all services"
  type        = bool
  default     = true
}

# ============================================================================
# SAGEMAKER CONFIGURATION
# ============================================================================

variable "sagemaker_training_instance" {
  description = "SageMaker training instance type"
  type        = string
  default     = "ml.p3.2xlarge"

  validation {
    condition     = can(regex("^ml\\.[a-z0-9]+$", var.sagemaker_training_instance))
    error_message = "Must be a valid SageMaker instance type (e.g., ml.p3.2xlarge)"
  }
}

variable "sagemaker_processing_instance" {
  description = "SageMaker processing instance type"
  type        = string
  default     = "ml.m5.2xlarge"

  validation {
    condition     = can(regex("^ml\\.[a-z0-9]+$", var.sagemaker_processing_instance))
    error_message = "Must be a valid SageMaker instance type"
  }
}

variable "sagemaker_notebook_instance" {
  description = "SageMaker notebook instance type"
  type        = string
  default     = "ml.t3.medium"

  validation {
    condition     = can(regex("^ml\\.[a-z0-9]+$", var.sagemaker_notebook_instance))
    error_message = "Must be a valid SageMaker instance type"
  }
}

variable "sagemaker_max_training_jobs" {
  description = "Maximum concurrent SageMaker training jobs"
  type        = number
  default     = 5

  validation {
    condition     = var.sagemaker_max_training_jobs > 0 && var.sagemaker_max_training_jobs <= 100
    error_message = "Must be between 1 and 100"
  }
}

variable "model_approval_threshold" {
  description = "Minimum accuracy threshold for automatic model approval"
  type        = number
  default     = 0.85

  validation {
    condition     = var.model_approval_threshold > 0 && var.model_approval_threshold <= 1
    error_message = "Must be between 0 and 1"
  }
}

# ============================================================================
# HEALTHIMAGING CONFIGURATION
# ============================================================================

variable "healthimaging_enable_logging" {
  description = "Enable detailed logging for HealthImaging"
  type        = bool
  default     = true
}

variable "healthimaging_log_retention" {
  description = "CloudWatch Logs retention in days"
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.healthimaging_log_retention)
    error_message = "Must be a valid CloudWatch retention value"
  }
}

# ============================================================================
# STORAGE CONFIGURATION
# ============================================================================

variable "training_data_retention_days" {
  description = "Retention period for training data in S3"
  type        = number
  default     = 90

  validation {
    condition     = var.training_data_retention_days > 0
    error_message = "Must be greater than 0"
  }
}

variable "enable_s3_versioning" {
  description = "Enable S3 bucket versioning"
  type        = bool
  default     = true
}

variable "enable_s3_intelligent_tiering" {
  description = "Enable S3 Intelligent-Tiering for cost optimization"
  type        = bool
  default     = true
}

# ============================================================================
# MONITORING & OBSERVABILITY
# ============================================================================

variable "cloudwatch_retention_days" {
  description = "CloudWatch Logs retention period in days"
  type        = number
  default     = 7

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_retention_days)
    error_message = "Must be a valid CloudWatch retention value"
  }
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed monitoring with 1-minute metrics"
  type        = bool
  default     = false  # High cost; enable only for prod
}

variable "sns_alert_topic_arn" {
  description = "SNS topic ARN for critical alerts"
  type        = string
  default     = ""

  validation {
    condition     = var.sns_alert_topic_arn == "" || can(regex("^arn:aws:sns:", var.sns_alert_topic_arn))
    error_message = "Must be a valid SNS topic ARN or empty string"
  }
}

# ============================================================================
# PERFORMANCE TUNING
# ============================================================================

variable "sagemaker_spot_instances" {
  description = "Use Spot instances for SageMaker training (70% cost savings)"
  type        = bool
  default     = false  # Keep false for prod; enable for dev/staging

  sensitive = false
}

variable "enable_sagemaker_autoscaling" {
  description = "Enable auto-scaling for SageMaker endpoints"
  type        = bool
  default     = true
}

variable "sagemaker_autoscaling_min_capacity" {
  description = "Minimum capacity for auto-scaled endpoints"
  type        = number
  default     = 1

  validation {
    condition     = var.sagemaker_autoscaling_min_capacity >= 1
    error_message = "Must be at least 1"
  }
}

variable "sagemaker_autoscaling_max_capacity" {
  description = "Maximum capacity for auto-scaled endpoints"
  type        = number
  default     = 4

  validation {
    condition     = var.sagemaker_autoscaling_max_capacity >= var.sagemaker_autoscaling_min_capacity
    error_message = "Must be >= min_capacity"
  }
}

# ============================================================================
# COMPLIANCE & SECURITY POLICIES
# ============================================================================

variable "enable_hipaa_compliance" {
  description = "Enable HIPAA compliance controls"
  type        = bool
  default     = true
}

variable "enable_data_residency_controls" {
  description = "Enforce data residency (no cross-region replication)"
  type        = bool
  default     = true
}

variable "require_mfa_for_destructive_operations" {
  description = "Require MFA for delete/destroy operations"
  type        = bool
  default     = true
}

variable "audit_log_retention_years" {
  description = "CloudTrail logs retention in years"
  type        = number
  default     = 7

  validation {
    condition     = var.audit_log_retention_years > 0 && var.audit_log_retention_years <= 10
    error_message = "Must be between 1 and 10 years"
  }
}

# ============================================================================
# FEATURE FLAGS
# ============================================================================

variable "enable_model_registry" {
  description = "Enable SageMaker Model Registry for model versioning"
  type        = bool
  default     = true
}

variable "enable_feature_store" {
  description = "Enable SageMaker Feature Store for feature management"
  type        = bool
  default     = false  # Optional; requires additional setup
}

variable "enable_model_monitor" {
  description = "Enable SageMaker Model Monitor for drift detection"
  type        = bool
  default     = true
}

variable "enable_inference_endpoints" {
  description = "Enable real-time inference endpoints for deployed models"
  type        = bool
  default     = false  # Deploy manually after pipeline validation
}

variable "enable_batch_inference" {
  description = "Enable batch inference for bulk processing"
  type        = bool
  default     = true
}

# ============================================================================
# TAGGING
# ============================================================================

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default = {
    Terraform   = "true"
    Module      = "HealthImaging-MLOps"
    Workshop    = "AWS-HealthTech-Accelerator"
  }
}

# ============================================================================
# OPTIONAL: LOCAL DEVELOPMENT
# ============================================================================

variable "enable_local_testing" {
  description = "Enable local testing resources (LocalStack, moto, etc.)"
  type        = bool
  default     = false
}

variable "docker_image_registry" {
  description = "Docker registry for container images"
  type        = string
  default     = ""  # Leave empty to use ECR

  validation {
    condition     = var.docker_image_registry == "" || can(regex("^([a-z0-9.-]+\\.)?dkr\\.ecr\\.[a-z0-9-]+\\.amazonaws\\.com$", var.docker_image_registry))
    error_message = "Must be a valid ECR registry URL or empty string"
  }
}
