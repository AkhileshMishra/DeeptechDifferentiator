# ============================================================================
# DEVELOPMENT ENVIRONMENT CONFIGURATION
# Healthcare Imaging MLOps Platform
# ============================================================================

# ============================================================================
# GENERAL SETTINGS
# ============================================================================

environment    = "dev"
project_name   = "healthcare-imaging-mlops"
aws_region     = "us-east-1"
aws_account_id = "YOUR_ACCOUNT_ID"  # Replace with your AWS account ID

# ============================================================================
# OWNER & COST TRACKING
# ============================================================================

owner_email = "your-email@example.com"  # Replace with your email
cost_center = "healthcare-dev"

# ============================================================================
# NETWORKING
# ============================================================================

vpc_cidr                = "10.0.0.0/16"
enable_nat_gateway      = true
flow_logs_retention_days = 7

# ============================================================================
# SAGEMAKER CONFIGURATION
# ============================================================================

# Development uses smaller instances for cost savings
sagemaker_training_instance   = "ml.p3.2xlarge"
sagemaker_processing_instance = "ml.m5.large"
sagemaker_notebook_instance   = "ml.t3.medium"

# ============================================================================
# STORAGE CONFIGURATION
# ============================================================================

training_data_retention_days = 30
logs_retention_days          = 7

# ============================================================================
# MONITORING
# ============================================================================

enable_detailed_monitoring = false
alarm_email               = "your-email@example.com"

# ============================================================================
# SECURITY
# ============================================================================

enable_encryption = true
enable_vpc_flow_logs = true

# ============================================================================
# COST OPTIMIZATION
# ============================================================================

# Use spot instances for training in dev
use_spot_instances = true
spot_max_price     = "1.50"  # Max price per hour for spot instances

# ============================================================================
# TAGS
# ============================================================================

additional_tags = {
  CostCenter  = "development"
  Team        = "ml-platform"
  Application = "healthcare-imaging"
}
