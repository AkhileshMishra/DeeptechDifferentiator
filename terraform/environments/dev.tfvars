aws_region     = "us-east-1"
# UPDATE THIS LINE with your real account ID
aws_account_id = "637423443220" 
project_name   = "healthcare-imaging"
environment    = "dev"
owner_email    = "admin@healthtech.com"
cost_center    = "dev-engineering"

vpc_cidr           = "10.10.0.0/16"
enable_nat_gateway = true

# Dev Sizing (Small/Cheap)
sagemaker_training_instance   = "ml.m5.xlarge"
sagemaker_processing_instance = "ml.m5.xlarge"
sagemaker_notebook_instance   = "ml.t3.medium"
sagemaker_spot_instances      = true
