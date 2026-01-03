# ============================================================================
# PRODUCTION ENVIRONMENT CONFIGURATION
# Healthcare Imaging MLOps Platform
# ============================================================================

# ============================================================================
# GENERAL SETTINGS
# ============================================================================

environment    = "prod"
project_name   = "healthcare-imaging-mlops"
aws_region     = "us-east-1"
aws_account_id = "YOUR_ACCOUNT_ID"  # Replace with your AWS account ID

# ============================================================================
# OWNER & COST TRACKING
# ============================================================================

owner_email = "your-email@example.com"  # Replace with your email
cost_center = "healthcare-prod"

# ============================================================================
# NETWORKING
# ============================================================================

vpc_cidr                = "10.1.0.0/16"
enable_nat_gateway      = true
flow_logs_retention_days = 90

# ============================================================================
# SAGEMAKER CONFIGURATION
# ============================================================================

# Production uses larger instances for performance
sagemaker_training_instance   = "ml.p3.8xlarge"
sagemaker_processing_instance = "ml.m5.xlarge"
sagemaker_notebook_instance   = "ml.t3.large"

# ============================================================================
# STORAGE CONFIGURATION
# ============================================================================

training_data_retention_days = 365
logs_retention_days          = 90

# ============================================================================
# MONITORING
# ============================================================================

enable_detailed_monitoring = true
alarm_email               = "ops-team@example.com"

# ============================================================================
# SECURITY
# ============================================================================

enable_encryption = true
enable_vpc_flow_logs = true

# ============================================================================
# COST OPTIMIZATION
# ============================================================================

# Use on-demand instances for production reliability
use_spot_instances = false
spot_max_price     = "0"

# ============================================================================
# HIGH AVAILABILITY
# ============================================================================

enable_multi_az = true
backup_retention_days = 30

# ============================================================================
# TAGS
# ============================================================================

additional_tags = {
  CostCenter  = "production"
  Team        = "ml-platform"
  Application = "healthcare-imaging"
  Compliance  = "HIPAA"
  DataClass   = "PHI"
}
