# ============================================================================
# SERVICE CONFIGURATION VARIABLES
# ============================================================================

# --- Networking ---
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
  
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid CIDR block"
  }
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnets"
  type        = bool
  default     = true
}

variable "flow_logs_retention_days" {
  description = "CloudWatch Logs retention period for VPC Flow Logs (days)"
  type        = number
  default     = 7
  
  validation {
    condition     = var.flow_logs_retention_days > 0 && var.flow_logs_retention_days <= 3653
    error_message = "Flow logs retention must be between 1 and 3653 days"
  }
}

# --- Security ---
variable "dicom_api_key" {
  description = "API key for DICOM service integration"
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

# --- SageMaker ---
variable "sagemaker_training_instance" {
  description = "EC2 instance type for SageMaker training jobs"
  type        = string
  default     = "ml.m5.xlarge"
  
  validation {
    condition     = can(regex("^ml\\.[a-z0-9]+\\.[a-z0-9]+$", var.sagemaker_training_instance))
    error_message = "Must be a valid SageMaker instance type (e.g., ml.m5.xlarge)"
  }
}

variable "sagemaker_processing_instance" {
  description = "EC2 instance type for SageMaker processing jobs"
  type        = string
  default     = "ml.m5.xlarge"
  
  validation {
    condition     = can(regex("^ml\\.[a-z0-9]+\\.[a-z0-9]+$", var.sagemaker_processing_instance))
    error_message = "Must be a valid SageMaker instance type (e.g., ml.m5.xlarge)"
  }
}

variable "sagemaker_notebook_instance" {
  description = "EC2 instance type for SageMaker notebook instances"
  type        = string
  default     = "ml.t3.medium"
  
  validation {
    condition     = can(regex("^ml\\.[a-z0-9]+\\.[a-z0-9]+$", var.sagemaker_notebook_instance))
    error_message = "Must be a valid SageMaker instance type (e.g., ml.t3.medium)"
  }
}

variable "sagemaker_spot_instances" {
  description = "Use Spot instances for SageMaker training to reduce costs"
  type        = bool
  default     = true
}

variable "enable_sagemaker_autoscaling" {
  description = "Enable auto-scaling for SageMaker endpoints"
  type        = bool
  default     = true
}

variable "sagemaker_autoscaling_min_capacity" {
  description = "Minimum capacity for SageMaker auto-scaling"
  type        = number
  default     = 1
  
  validation {
    condition     = var.sagemaker_autoscaling_min_capacity >= 1
    error_message = "Minimum capacity must be at least 1"
  }
}

variable "sagemaker_autoscaling_max_capacity" {
  description = "Maximum capacity for SageMaker auto-scaling"
  type        = number
  default     = 2
  
  validation {
    condition     = var.sagemaker_autoscaling_max_capacity >= var.sagemaker_autoscaling_min_capacity
    error_message = "Maximum capacity must be greater than or equal to minimum capacity"
  }
}

variable "model_approval_threshold" {
  description = "Model accuracy threshold for automatic approval"
  type        = number
  default     = 0.85
  
  validation {
    condition     = var.model_approval_threshold > 0 && var.model_approval_threshold <= 1
    error_message = "Model approval threshold must be between 0 and 1"
  }
}

# --- HealthImaging ---
variable "healthimaging_enable_logging" {
  description = "Enable CloudWatch logging for HealthImaging"
  type        = bool
  default     = true
}

variable "healthimaging_log_retention" {
  description = "CloudWatch Logs retention period for HealthImaging (days)"
  type        = number
  default     = 30
  
  validation {
    condition     = var.healthimaging_log_retention > 0 && var.healthimaging_log_retention <= 3653
    error_message = "Log retention must be between 1 and 3653 days"
  }
}

# --- Storage ---
variable "training_data_retention_days" {
  description = "S3 lifecycle policy: delete training data after N days"
  type        = number
  default     = 90
  
  validation {
    condition     = var.training_data_retention_days > 0
    error_message = "Training data retention must be greater than 0 days"
  }
}

variable "enable_s3_versioning" {
  description = "Enable versioning on S3 buckets for data protection"
  type        = bool
  default     = true
}

variable "enable_s3_intelligent_tiering" {
  description = "Enable S3 Intelligent-Tiering for automatic cost optimization"
  type        = bool
  default     = true
}

# --- Observability ---
variable "cloudwatch_retention_days" {
  description = "CloudWatch Logs retention period for application logs (days)"
  type        = number
  default     = 7
  
  validation {
    condition     = var.cloudwatch_retention_days > 0 && var.cloudwatch_retention_days <= 3653
    error_message = "CloudWatch retention must be between 1 and 3653 days"
  }
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring (higher cost)"
  type        = bool
  default     = false
}

variable "sns_alert_topic_arn" {
  description = "SNS topic ARN for CloudWatch alarms and notifications"
  type        = string
  default     = ""
}

# --- Tags ---
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
  
  validation {
    condition = alltrue([
      for k, v in var.additional_tags : can(regex("^[a-zA-Z0-9_:./=+\\-@]*$", k)) && can(regex("^[a-zA-Z0-9_:./=+\\-@]*$", v))
    ])
    error_message = "Tag keys and values must contain only alphanumeric characters and the special characters: _ : . / = + - @"
  }
}
