# ============================================================================
# SERVICE CONFIGURATION VARIABLES
# ============================================================================

# --- Networking ---
variable "vpc_cidr" { default = "10.0.0.0/16" }
variable "enable_nat_gateway" { default = true }
variable "flow_logs_retention_days" { default = 7 }

# --- Security ---
variable "dicom_api_key" { sensitive = true, default = "" }
variable "enable_vpc_endpoints" { default = true }
variable "enable_encryption" { default = true }

# --- SageMaker ---
variable "sagemaker_training_instance" { default = "ml.m5.xlarge" }
variable "sagemaker_processing_instance" { default = "ml.m5.xlarge" }
variable "sagemaker_notebook_instance" { default = "ml.t3.medium" }
variable "sagemaker_spot_instances" { default = true }
variable "enable_sagemaker_autoscaling" { default = true }
variable "sagemaker_autoscaling_min_capacity" { default = 1 }
variable "sagemaker_autoscaling_max_capacity" { default = 2 }
variable "model_approval_threshold" { default = 0.85 }

# --- HealthImaging ---
variable "healthimaging_enable_logging" { default = true }
variable "healthimaging_log_retention" { default = 30 }

# --- Storage ---
variable "training_data_retention_days" { default = 90 }
variable "enable_s3_versioning" { default = true }
variable "enable_s3_intelligent_tiering" { default = true }

# --- Observability ---
variable "cloudwatch_retention_days" { default = 7 }
variable "enable_detailed_monitoring" { default = false }
variable "sns_alert_topic_arn" { default = "" }

# --- Tags ---
variable "additional_tags" {
  type    = map(string)
  default = {}
}
