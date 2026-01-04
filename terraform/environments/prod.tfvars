aws_region     = "us-east-1"
aws_account_id = "YOUR_PROD_ACCOUNT_ID"
project_name   = "healthcare-imaging"
environment    = "prod"
owner_email    = "ops-team@example.com"
cost_center    = "prod-engineering"

vpc_cidr           = "10.30.0.0/16"
enable_nat_gateway = true

# Prod Sizing (High Perf/High Availability)
sagemaker_training_instance   = "ml.p3.2xlarge"
sagemaker_processing_instance = "ml.c5.2xlarge"
sagemaker_notebook_instance   = "ml.t3.xlarge"
sagemaker_spot_instances      = false
sagemaker_autoscaling_min_capacity = 2
