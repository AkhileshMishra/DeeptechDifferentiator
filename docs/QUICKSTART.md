# terraform/environments/dev.tfvars
# Development Environment Configuration

# Core Settings
aws_region     = "us-east-1"
aws_account_id = "123456789012"  # Replace with your account ID
project_name   = "healthcare-imaging"
environment    = "dev"
owner_email    = "devops@example.com"
cost_center    = "engineering"

# Networking
vpc_cidr              = "10.0.0.0/16"
enable_nat_gateway    = true
flow_logs_retention_days = 7

# Security
enable_vpc_endpoints = true
enable_encryption    = true
enable_hipaa_compliance = true
enable_data_residency_controls = true

# SageMaker Configuration
sagemaker_training_instance = "ml.p3.2xlarge"
sagemaker_processing_instance = "ml.m5.2xlarge"
sagemaker_notebook_instance = "ml.t3.medium"
sagemaker_max_training_jobs = 5
model_approval_threshold = 0.85

# Use Spot instances for cost savings in dev
sagemaker_spot_instances = true
enable_sagemaker_autoscaling = true
sagemaker_autoscaling_min_capacity = 1
sagemaker_autoscaling_max_capacity = 4

# HealthImaging
healthimaging_enable_logging = true
healthimaging_log_retention = 7

# Storage
training_data_retention_days = 90
enable_s3_versioning = true
enable_s3_intelligent_tiering = true

# Monitoring
cloudwatch_retention_days = 7
enable_detailed_monitoring = false  # Cost optimization for dev
sns_alert_topic_arn = ""  # Set to your SNS topic ARN if needed

# Compliance
audit_log_retention_years = 7
require_mfa_for_destructive_operations = false  # Relaxed for dev

# Feature Flags
enable_model_registry = true
enable_feature_store = false
enable_model_monitor = true
enable_inference_endpoints = false  # Enable after validation
enable_batch_inference = true

# Local Development
enable_local_testing = false
docker_image_registry = ""

---

# terraform/environments/prod.tfvars
# Production Environment Configuration

aws_region     = "us-east-1"
aws_account_id = "987654321098"  # Replace with your account ID
project_name   = "healthcare-imaging"
environment    = "prod"
owner_email    = "healthcare-ops@example.com"
cost_center    = "clinical-ai"

# Networking
vpc_cidr              = "10.0.0.0/16"
enable_nat_gateway    = true
flow_logs_retention_days = 30

# Security - All strict for production
enable_vpc_endpoints = true
enable_encryption    = true
enable_hipaa_compliance = true
enable_data_residency_controls = true

# SageMaker - Higher capacity
sagemaker_training_instance = "ml.p3.8xlarge"  # Multi-GPU training
sagemaker_processing_instance = "ml.m5.4xlarge"
sagemaker_notebook_instance = "ml.t3.xlarge"
sagemaker_max_training_jobs = 10
model_approval_threshold = 0.88  # Higher threshold in production

# Use Reserved Capacity (not Spot) for stability
sagemaker_spot_instances = false
enable_sagemaker_autoscaling = true
sagemaker_autoscaling_min_capacity = 2
sagemaker_autoscaling_max_capacity = 10

# HealthImaging - Detailed logging
healthimaging_enable_logging = true
healthimaging_log_retention = 365

# Storage - Long retention
training_data_retention_days = 365  # 1-year retention for audit
enable_s3_versioning = true
enable_s3_intelligent_tiering = true

# Monitoring - Detailed in production
cloudwatch_retention_days = 30
enable_detailed_monitoring = true  # 1-minute metrics for prod
sns_alert_topic_arn = "arn:aws:sns:us-east-1:987654321098:healthcare-alerts"

# Compliance - Maximum for production
audit_log_retention_years = 7
require_mfa_for_destructive_operations = true

# All features enabled in production
enable_model_registry = true
enable_feature_store = true
enable_model_monitor = true
enable_inference_endpoints = true
enable_batch_inference = true

enable_local_testing = false
docker_image_registry = ""

---

# DEPLOYMENT_GUIDE.md
## Quick Start: Deploy Healthcare Imaging MLOps Platform

### Prerequisites (5 minutes)

```bash
# 1. Install required tools
brew install terraform aws-cli
aws --version          # AWS CLI v2.x+
terraform --version    # Terraform 1.0+

# 2. Configure AWS credentials
aws configure
# Enter: Access Key, Secret Key, Region (us-east-1), Output format (json)

# 3. Verify AWS access
aws sts get-caller-identity
# Output should show your Account ID, User ARN, etc.

# 4. Clone repository
git clone <repo-url>
cd healthcare-imaging-mlops

# 5. Set environment variables
export PROJECT_NAME=healthcare-imaging
export ENVIRONMENT=dev
export AWS_REGION=us-east-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "Account ID: $AWS_ACCOUNT_ID"
```

### Step 1: Configure Terraform (2 minutes)

```bash
cd terraform

# Copy dev template
cp environments/dev.tfvars terraform.tfvars

# Edit with your values
nano terraform.tfvars

# Key values to customize:
#  - aws_account_id: Your AWS Account ID
#  - owner_email: Your email
#  - sns_alert_topic_arn: Your SNS topic (optional)
```

### Step 2: Initialize Terraform (3 minutes)

```bash
terraform init

# Output should show:
# ✓ Terraform has been successfully configured!
```

### Step 3: Review & Plan Deployment (5 minutes)

```bash
terraform plan \
  -var="aws_region=$AWS_REGION" \
  -var="aws_account_id=$AWS_ACCOUNT_ID" \
  -out=tfplan

# Review the plan carefully:
# - Read all resources being created
# - Verify counts match expectations (~35-40 resources)
# - Check for any errors or warnings
```

### Step 4: Apply Infrastructure (15-20 minutes)

```bash
# This creates all AWS resources
terraform apply tfplan

# Monitor the progress
# You should see: "Apply complete! Resources: X added, 0 changed, 0 destroyed."

# Save outputs
terraform output -json > deployment-info.json
cat deployment-info.json
```

### Step 5: Verify Deployment (5 minutes)

```bash
# Extract key outputs
HEALTHIMAGING_DATASTORE=$(terraform output -raw healthimaging_data_store_id)
SAGEMAKER_PIPELINE=$(terraform output -raw sagemaker_pipeline_name)
TRAINING_BUCKET=$(terraform output -raw training_data_bucket)

echo "HealthImaging Data Store: $HEALTHIMAGING_DATASTORE"
echo "SageMaker Pipeline: $SAGEMAKER_PIPELINE"
echo "Training Data Bucket: $TRAINING_BUCKET"

# Test HealthImaging access
aws medical-imaging get-data-store \
  --data-store-id "$HEALTHIMAGING_DATASTORE" \
  --region "$AWS_REGION"

# Test SageMaker Pipeline
aws sagemaker describe-pipeline \
  --pipeline-name "$SAGEMAKER_PIPELINE" \
  --region "$AWS_REGION"

# Expected output: JSON describing the pipeline
```

### Step 6: Test End-to-End (10 minutes)

```bash
# 1. Create test DICOM file (or use real sample)
cd ../python
python scripts/generate-sample-dicom.py \
  --output sample-chest-ct.dcm \
  --modality CT \
  --frames 512

# 2. Upload to training bucket
aws s3 cp sample-chest-ct.dcm \
  "s3://${TRAINING_BUCKET}/upload/test-dicom-$(date +%s).dcm"

# 3. Monitor image ingestion in CloudWatch
aws logs tail /aws/lambda/image-ingestion --follow

# Expected log output: "Image validated and ingested successfully"

# 4. Verify image in HealthImaging
aws medical-imaging search-image-sets \
  --data-store-id "$HEALTHIMAGING_DATASTORE" \
  --region "$AWS_REGION"

# 5. Trigger SageMaker pipeline (manual test)
aws sagemaker start-pipeline-execution \
  --pipeline-name "$SAGEMAKER_PIPELINE" \
  --region "$AWS_REGION" \
  --pipeline-parameters \
    ParameterName=TrainingDataPath,ParameterStringValue="s3://${TRAINING_BUCKET}/verified/" \
    ParameterName=AccuracyThreshold,ParameterValue="0.85"

# 6. Monitor pipeline execution
aws sagemaker list-pipeline-executions \
  --pipeline-name "$SAGEMAKER_PIPELINE" \
  --region "$AWS_REGION" \
  --sort-order Descending \
  --sort-by CreationTime

# Wait for status: "Succeeded" or "Failed"
```

### Step 7: Access CloudWatch Dashboards (2 minutes)

```bash
# Get dashboard URLs
terraform output monitoring_dashboards

# Open in browser:
# https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:

# You should see 3 dashboards:
#  1. HealthImaging Dashboard (retrieval latency, data volume)
#  2. SageMaker Pipeline Dashboard (training metrics, accuracy)
#  3. MLOps Dashboard (data quality, model performance)
```

---

## Common Operations

### Trigger Training Pipeline Manually

```bash
TRAINING_DATA_PATH="s3://$(aws s3 ls | grep training-data | awk '{print $NF}' | head -1)/verified/"

aws sagemaker start-pipeline-execution \
  --pipeline-name "$SAGEMAKER_PIPELINE" \
  --pipeline-parameters \
    ParameterName=TrainingDataPath,ParameterStringValue="$TRAINING_DATA_PATH" \
    ParameterName=AccuracyThreshold,ParameterValue="0.85"
```

### Stream DICOM to Mobile Browser

```bash
# Generate streaming URL (via Lambda API)
curl -X POST https://api-endpoint.example.com/stream \
  -H "Content-Type: application/json" \
  -d '{
    "image_set_id": "img-12345",
    "expiration_minutes": 60
  }'

# Response:
# {
#   "streaming_url": "https://imaging.us-east-1.amazonaws.com/datastore/...",
#   "expires_in": 3600
# }

# Open URL in mobile browser → Real-time DICOM viewing at 60fps
```

### View Model Performance Metrics

```bash
aws dynamodb scan \
  --table-name "healthcare-imaging-dev-model-metrics" \
  --region "$AWS_REGION" \
  --projection-expression "model_version, accuracy, precision, recall" \
  --output table
```

### Check Lambda Function Logs

```bash
# Image Ingestion
aws logs tail /aws/lambda/image-ingestion --follow

# Pipeline Trigger
aws logs tail /aws/lambda/pipeline-trigger --follow

# Model Evaluation
aws logs tail /aws/lambda/model-evaluation --follow

# Model Registry
aws logs tail /aws/lambda/model-registry --follow
```

---

## Cleanup (Destroy Resources)

```bash
# ⚠️ CAUTION: This will delete all resources and data!

cd terraform

# First, backup any important data
aws s3 sync "s3://${TRAINING_BUCKET}/" ./backup/training-data/
aws s3 sync "s3://$(aws s3 ls | grep model-artifacts | awk '{print $NF}' | head -1)" ./backup/models/

# Destroy infrastructure
terraform destroy -var-file=terraform.tfvars

# Confirm: type "yes" when prompted

# Verify deletion
aws ec2 describe-instances --region "$AWS_REGION" --filters "Name=tag:Environment,Values=dev"
# Output should be empty
```

---

## Troubleshooting

### Issue: Terraform Init Fails with "Backend Configuration"

**Solution**:
```bash
rm -rf .terraform/
terraform init -reconfigure
```

### Issue: HealthImaging Data Store Creation Fails

**Solution**:
```bash
# Verify service availability in your region
aws medical-imaging list-data-stores --region "$AWS_REGION"

# Check IAM permissions
aws iam get-user

# Verify KMS key exists
aws kms list-keys --region "$AWS_REGION"
```

### Issue: Lambda Functions Not Triggering

**Solution**:
```bash
# Check EventBridge rules
aws events list-rules --event-bus-name "healthcare-imaging-dev-events"

# Check Lambda IAM permissions
aws iam get-role --role-name "healthcare-imaging-dev-lambda-image-ingestion"

# Test EventBridge rule manually
aws events put-events \
  --entries '[{
    "Source": "aws.healthimaging",
    "DetailType": "HealthImaging ImageVerified",
    "Detail": "{\"imageSetId\": \"test-123\"}"
  }]'
```

### Issue: SageMaker Pipeline Fails

**Solution**:
```bash
# Get pipeline execution details
EXECUTION_ARN=$(aws sagemaker list-pipeline-executions \
  --pipeline-name "$SAGEMAKER_PIPELINE" \
  --sort-order Descending \
  --query 'PipelineExecutionSummaries[0].PipelineExecutionArn' \
  --output text)

# Describe execution
aws sagemaker describe-pipeline-execution \
  --pipeline-execution-arn "$EXECUTION_ARN"

# Check CloudWatch logs
aws logs tail /aws/sagemaker/training-jobs --follow
```

### Issue: High Costs in Development

**Solution**:
```bash
# Enable Spot Instances for training (70% savings)
# In dev.tfvars:
sagemaker_spot_instances = true

# Apply changes
terraform apply

# Use smaller instances
sagemaker_training_instance = "ml.g4dn.xlarge"  # GPU at lower cost
```

---

## Next Steps

1. **Deploy ML Models**: Run the SageMaker pipeline with real training data
2. **Enable Inference**: Deploy model to real-time endpoint for diagnostic support
3. **Integrate with PACS**: Connect to hospital PACS system for automatic DICOM ingestion
4. **Implement CI/CD**: Add GitHub Actions for automated tests and deployments
5. **Scale to Production**: Apply same infrastructure to production account
6. **Monitor for Drift**: Implement SageMaker Model Monitor for continuous model quality

---

## Support & Documentation

- **Architecture**: See `ARCHITECTURE.md`
- **API Reference**: See `docs/API.md`
- **HealthImaging Guide**: See `docs/DICOM_STREAMING.md`
- **ML Pipeline Guide**: See `docs/MLOPS_PIPELINE.md`
- **HIPAA Compliance**: See `docs/COMPLIANCE.md`

---

**Estimated Time**: 45 minutes from start to deployed, tested system

**Cost**: ~$30-50 for a 1-hour proof of concept (excluding reserved hours)

**Questions?** Email: healthcare-support@example.com
