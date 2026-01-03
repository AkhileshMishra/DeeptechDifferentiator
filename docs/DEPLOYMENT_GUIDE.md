# Deployment Guide

## Healthcare Imaging MLOps Platform - Complete Deployment Guide

**Module 3 Workshop Implementation**  
**Duration: 45 Minutes (Total)**  
**Complexity: Advanced**

---

## Table of Contents
1. [Prerequisites (5 min)](#prerequisites)
2. [Environment Setup (10 min)](#environment-setup)
3. [Infrastructure Deployment (15 min)](#infrastructure-deployment)
4. [Validation & Testing (10 min)](#validation-testing)
5. [Workshop Demo (Optional - 20 min)](#workshop-demo)
6. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Software
```bash
# Check versions (minimum requirements)
aws --version        # AWS CLI v2.13+
terraform --version  # Terraform 1.5+
python --version     # Python 3.9+
git --version        # Git 2.40+

# Installation (macOS with Homebrew)
brew install awscli terraform python git

# Installation (Ubuntu/Debian)
sudo apt-get install awscli terraform python3 git

# Installation (Windows with Chocolatey)
choco install awscli terraform python git
```

### AWS Account Requirements
- ✅ Active AWS Account
- ✅ AdministratorAccess IAM role (or equivalent)
- ✅ Sufficient service limits:
  - ✅ SageMaker: Training job quota ≥ 2
  - ✅ EC2: GPU instance quota ≥ 1 (p3.2xlarge)
  - ✅ VPC: VPCs ≤ 5 per region
  - ✅ S3: Buckets ≤ 100 per account
  - ✅ HealthImaging: Service enabled in region
- ✅ US-East-1 region (or modify for your region)

### AWS Credentials Setup
```bash
# Configure credentials
aws configure

# Provide:
# AWS Access Key ID: [your key]
# AWS Secret Access Key: [your secret]
# Default region: us-east-1
# Default output format: json

# Verify
aws sts get-caller-identity
# Should return your AccountId and ARN
```

### GitHub Setup (Optional, for CI/CD)
```bash
# Generate personal access token
# Visit: https://github.com/settings/tokens
# Scope: repo, admin:repo_hook

# Clone repository
git clone https://github.com/your-org/healthcare-imaging-mlops.git
cd healthcare-imaging-mlops
```

---

## Environment Setup

### Step 1: Clone Repository
```bash
git clone https://github.com/your-org/healthcare-imaging-mlops.git
cd healthcare-imaging-mlops

# Verify structure
ls -la
# Should show: terraform/, python/, scripts/, docs/, .github/
```

### Step 2: Verify Directory Structure
```bash
# Verify critical files exist
test -f terraform/main.tf && echo "✓ main.tf found"
test -f terraform/variables.tf && echo "✓ variables.tf found"
test -f python/requirements.txt && echo "✓ requirements.txt found"
test -f scripts/deploy.sh && echo "✓ deploy.sh found"

# All should print "✓"
```

### Step 3: Set Environment Variables
```bash
# Copy template and edit
cp terraform/environments/dev.tfvars terraform.tfvars

# Edit with your values
nano terraform.tfvars

# Required values to change:
# - aws_account_id = "YOUR_ACCOUNT_ID"
# - aws_region = "us-east-1"  
# - owner_email = "your-email@example.com"
# - environment = "dev"
# - project_name = "healthcare-imaging"
```

### Step 4: Install Python Dependencies
```bash
# Create virtual environment
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install --upgrade pip
pip install -r python/requirements.txt

# Verify
python -c "import boto3, sagemaker, tensorflow; print('✓ All dependencies installed')"
```

### Step 5: Verify AWS Permissions
```bash
# Check if user can perform required actions
aws iam get-user

# Check if region supports HealthImaging
aws healthimaging list-data-stores --region us-east-1

# If error: "BadRequestException", HealthImaging may not be available in your region
# Supported regions: us-east-1, eu-west-1, ap-southeast-2
```

---

## Infrastructure Deployment

### Step 1: Initialize Terraform
```bash
cd terraform

# Initialize backend and download providers
terraform init

# Expected output:
# Terraform has been successfully configured!

# Verify initialization
test -d .terraform && echo "✓ Terraform initialized"
```

### Step 2: Validate Terraform Configuration
```bash
# Validate syntax and structure
terraform validate

# Expected output:
# Success! The configuration is valid.
```

### Step 3: Plan Deployment
```bash
# Generate execution plan (dry-run)
terraform plan -out=tfplan

# Expected output:
# Plan: 40 to add, 0 to change, 0 to destroy.
# 
# Save this plan to Terraform state upon 'terraform apply'

# Review critical resources:
# - aws_healthimaging_datastore
# - aws_sagemaker_pipeline_definition
# - aws_lambda_function (4 functions)
# - aws_s3_bucket (5 buckets)
# - aws_dynamodb_table
# - aws_cloudwatch_dashboard
```

### Step 4: Apply Infrastructure
```bash
# Deploy infrastructure
terraform apply tfplan

# Duration: 10-15 minutes
# Watch for:
# ✓ HealthImaging datastore created
# ✓ SageMaker pipeline registered
# ✓ Lambda functions deployed
# ✓ S3 buckets created
# ✓ DynamoDB tables created
# ✓ CloudWatch dashboards created

# Expected final output:
# Apply complete! Resources added: 40
# 
# Outputs:
# healthimaging_datastore_id = "xxx"
# sagemaker_pipeline_name = "healthcare-imaging-training-pipeline"
# training_bucket = "s3://xxx-training-xxx"
# ...
```

### Step 5: Capture Outputs
```bash
# Save deployment outputs
terraform output > deployment_outputs.txt

# Extract key values for later use
HEALTHIMAGING_DATASTORE_ID=$(terraform output -raw healthimaging_datastore_id)
SAGEMAKER_PIPELINE_NAME=$(terraform output -raw sagemaker_pipeline_name)
TRAINING_BUCKET=$(terraform output -raw training_bucket)
IMAGE_INGESTION_LAMBDA=$(terraform output -raw image_ingestion_lambda_name)

# Verify
echo "HealthImaging Datastore: $HEALTHIMAGING_DATASTORE_ID"
echo "SageMaker Pipeline: $SAGEMAKER_PIPELINE_NAME"
echo "Training Bucket: $TRAINING_BUCKET"
echo "Ingestion Lambda: $IMAGE_INGESTION_LAMBDA"
```

### Step 6: Build and Push Docker Images
```bash
# Navigate to docker directory
cd ../docker

# Create ECR repositories (if not created by Terraform)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=us-east-1

# Login to ECR
aws ecr get-login-password --region $REGION | \
  docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

# Build and push preprocessing image
cd sagemaker/preprocessing
docker build -t healthcare-preprocessing:latest .
docker tag healthcare-preprocessing:latest $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/healthcare-preprocessing:latest
docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/healthcare-preprocessing:latest

# Build and push training image
cd ../training
docker build -t healthcare-training:latest .
docker tag healthcare-training:latest $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/healthcare-training:latest
docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/healthcare-training:latest

# Build and push evaluation image
cd ../evaluation
docker build -t healthcare-evaluation:latest .
docker tag healthcare-evaluation:latest $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/healthcare-evaluation:latest
docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/healthcare-evaluation:latest

# Build and push inference image
cd ../inference
docker build -t healthcare-inference:latest .
docker tag healthcare-inference:latest $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/healthcare-inference:latest
docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/healthcare-inference:latest

# Verify
aws ecr describe-repositories --region $REGION
# Should list 4 repositories: healthcare-preprocessing, healthcare-training, healthcare-evaluation, healthcare-inference
```

---

## Validation & Testing

### Step 1: Verify AWS Resources
```bash
# Check HealthImaging datastore
aws healthimaging list-data-stores \
  --region us-east-1 \
  --output table

# Check SageMaker pipeline
aws sagemaker describe-pipeline \
  --pipeline-name healthcare-imaging-training-pipeline \
  --region us-east-1

# Check S3 buckets
aws s3 ls | grep healthcare

# Check Lambda functions
aws lambda list-functions \
  --region us-east-1 \
  --output table | grep healthcare

# Check DynamoDB tables
aws dynamodb list-tables \
  --region us-east-1 \
  --output table
```

### Step 2: Run Deployment Validation Script
```bash
cd scripts

# Make script executable
chmod +x validate-deployment.sh

# Run validation
./validate-deployment.sh

# Expected output:
# ✓ Terraform state exists
# ✓ HealthImaging datastore accessible
# ✓ SageMaker pipeline registered
# ✓ S3 buckets accessible
# ✓ Lambda functions deployed
# ✓ DynamoDB tables created
# ✓ CloudWatch dashboards available
# ✓ IAM roles have proper permissions
# ✓ KMS keys accessible
# ✓ VPC endpoints configured
# 
# All validation checks passed! ✓
```

### Step 3: Generate Test DICOM Image
```bash
# Generate synthetic chest CT DICOM file
python generate-sample-dicom.py \
  --output test-chest-ct.dcm \
  --frames 200 \
  --size 512x512

# Expected output:
# Generated synthetic DICOM: test-chest-ct.dcm
# File size: ~1.2 GB (matches production scenario)
# Contains: 200 CT slices
```

### Step 4: Test Image Ingestion
```bash
# Get bucket name
TRAINING_BUCKET=$(terraform output -raw training_bucket)

# Upload test DICOM to ingestion folder
aws s3 cp test-chest-ct.dcm \
  s3://$TRAINING_BUCKET/upload/test-chest-ct.dcm

# Watch Lambda execution logs
aws logs tail /aws/lambda/image-ingestion --follow

# Expected log entries:
# [INFO] Processing s3://xxx/upload/test-chest-ct.dcm
# [INFO] Uploading to HealthImaging datastore
# [INFO] Datastore ID: xxx
# [INFO] Image set ID: xxx
# [INFO] Putting metadata in DynamoDB
# [SUCCESS] Image ingestion complete

# Verify image in HealthImaging
aws healthimaging search-image-sets \
  --data-store-id $HEALTHIMAGING_DATASTORE_ID \
  --filters '[{"values": ["test-chest-ct"]}]'
```

### Step 5: Test Pipeline Trigger (Manual)
```bash
# Update image status to "verified" in DynamoDB
aws dynamodb update-item \
  --table-name healthcare-imaging-metadata \
  --key '{"image_id": {"S": "test-chest-ct"}}' \
  --update-expression "SET #status = :status" \
  --expression-attribute-names '{"#status": "status"}' \
  --expression-attribute-values '{":status": {"S": "verified"}}'

# This triggers EventBridge rule → Lambda → SageMaker Pipeline

# Watch pipeline execution
aws logs tail /aws/lambda/pipeline-trigger --follow

# Expected log entries:
# [INFO] EventBridge event received
# [INFO] Image status changed to verified
# [INFO] Starting SageMaker Pipeline
# [INFO] Pipeline execution ID: xxx
# [SUCCESS] Pipeline triggered successfully

# Verify pipeline execution
aws sagemaker list-pipeline-executions \
  --pipeline-name healthcare-imaging-training-pipeline \
  --sort-order Descending \
  --max-items 5

# Should show recent execution in "Executing" or "Succeeded" state
```

### Step 6: Monitor Pipeline Execution
```bash
# Get latest pipeline execution ID
EXECUTION_ID=$(aws sagemaker list-pipeline-executions \
  --pipeline-name healthcare-imaging-training-pipeline \
  --sort-order Descending \
  --max-items 1 \
  --query 'PipelineExecutionSummaries[0].PipelineExecutionArn' \
  --output text)

# Check execution status
aws sagemaker describe-pipeline-execution \
  --pipeline-execution-arn $EXECUTION_ID

# Expected output shows:
# PipelineExecutionStatus: Executing (or Succeeded)
# Steps: Preprocessing → Training → Evaluation → Approval

# Watch CloudWatch logs
aws logs tail /aws/sagemaker/ProcessingJobs/healthcare-imaging-preprocessing --follow

# Expected final state after ~20 minutes:
# [SUCCESS] Model accuracy: 0.87
# [SUCCESS] ROC-AUC score: 0.91
# [SUCCESS] Model registered: healthcare-imaging-pneumonia-v1
```

### Step 7: Verify CloudWatch Dashboards
```bash
# List dashboards
aws cloudwatch list-dashboards | grep healthcare

# Expected output shows:
# - healthcare-imaging-overview
# - healthcare-imaging-sagemaker
# - healthcare-imaging-healthimaging

# View dashboard (via AWS Console for visual verification)
echo "Open AWS Console: https://console.aws.amazon.com/cloudwatch"
echo "Navigate to Dashboards → healthcare-imaging-overview"
echo "Expected metrics:"
echo "  - HealthImaging API latency: < 1000ms"
echo "  - Lambda invocations: > 0"
echo "  - SageMaker training duration: < 30 minutes"
echo "  - DynamoDB read/write throughput: active"
```

### Step 8: Run Integration Tests
```bash
cd ../python/tests

# Run unit tests
pytest unit/ -v --tb=short

# Run integration tests (requires AWS credentials)
pytest integration/ -v --tb=short

# Expected output:
# test_healthimaging_client.py::test_list_data_stores PASSED
# test_sagemaker_pipeline.py::test_describe_pipeline PASSED
# test_lambda_handlers.py::test_image_ingestion_handler PASSED
# test_dynamodb.py::test_metadata_storage PASSED
# 
# 20 passed in 45.23s
```

---

## Workshop Demo

### Demo Setup (5 minutes before presentation)

```bash
# 1. Generate fresh test DICOM
cd scripts
python generate-sample-dicom.py --output demo-ct.dcm

# 2. Verify infrastructure is running
aws ec2 describe-security-groups --query 'SecurityGroups[0].GroupId'

# 3. Pre-upload DICOM (so upload is instant during demo)
TRAINING_BUCKET=$(terraform output -raw training_bucket)
aws s3 cp demo-ct.dcm s3://$TRAINING_BUCKET/upload/

# 4. Open CloudWatch dashboards in browser tabs
# Tab 1: https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:name=healthcare-imaging-overview
# Tab 2: https://console.aws.amazon.com/sagemaker/home?region=us-east-1#/pipelines
# Tab 3: https://console.aws.amazon.com/healthimaging/home?region=us-east-1#/dataStores

# 5. Open Lambda logs in terminal
aws logs tail /aws/lambda/image-ingestion --follow &
aws logs tail /aws/sagemaker/ProcessingJobs/healthcare-imaging-preprocessing --follow &

# 6. Position windows for live demo viewing
```

### Demo Script (35 minutes)

#### Part 1: The Setup & Problem Statement (5 minutes)
```
PRESENTER: "Doctors cannot wait for 1GB files to download. 
Data scientists cannot manually retrain models every time a new 
image comes in. Let me show you how we solved both problems."

SLIDE: Problem-Solution diagram

ACTION: Click through AWS architecture diagram
```

#### Part 2: Zero-Latency Streaming Demo (15 minutes)
```
PRESENTER: "First, let's upload a massive chest CT scan to 
AWS HealthImaging and access it instantly on a mobile browser."

ACTION 1: Upload DICOM
$ aws s3 cp demo-ct.dcm s3://$TRAINING_BUCKET/upload/demo-ct.dcm
(Watch logs show ingestion success)

ACTION 2: Share viewer link
$ VIEWER_LINK=$(terraform output -raw dicom_viewer_url)
$ echo "Viewer URL: $VIEWER_LINK"

ACTION 3: Open in mobile browser (or simulate with responsive view)
- Navigate to viewer URL
- Scroll through CT slices
- Point out: "No buffering, no download wait, 60fps on 4G"

METRIC TO SHOW:
- CloudWatch: HealthImaging API latency < 500ms
- CloudWatch: Network throughput: 50+ Mbps

TALKING POINTS:
- HTJ2K compression: 40% smaller than standard JPEG
- HealthImaging: sub-second slice retrieval
- Mobile-first design: responsive, works on tablets/phones
```

#### Part 3: Automated Training CI/CD Demo (12 minutes)
```
PRESENTER: "Now, when the radiologist verifies this image 
as ground truth, the system automatically triggers a complete 
training pipeline. No manual intervention."

ACTION 1: Mark image as verified
$ aws dynamodb update-item \
  --table-name healthcare-imaging-metadata \
  --key '{"image_id": {"S": "demo-ct"}}' \
  --update-expression "SET #status = :status" \
  --expression-attribute-values '{":status": {"S": "verified"}}'
(Watch logs show EventBridge rule triggered)

ACTION 2: Show SageMaker pipeline activation
$ aws sagemaker list-pipeline-executions \
  --pipeline-name healthcare-imaging-training-pipeline \
  --sort-order Descending \
  --max-items 1

(Point to CloudWatch: Pipeline now "Executing")

ACTION 3: Explain pipeline steps (show in SageMaker console)
- Step 1 (Preprocessing): 3 minutes
  "Normalizing DICOM slices, augmenting data..."
- Step 2 (Training): 15 minutes
  "GPU training on p3.2xlarge, ResNet-50 architecture..."
- Step 3 (Evaluation): 2 minutes
  "Computing accuracy, precision, recall, ROC-AUC..."
- Step 4 (Approval): Conditional
  "If accuracy > 85%, auto-approve; else require manual review"

ACTION 4: Show real-time logs
$ aws logs tail /aws/sagemaker/ProcessingJobs/healthcare-imaging-preprocessing --follow

(Watch metrics in real-time on CloudWatch dashboard)

METRICS TO SHOW:
- CloudWatch: Lambda execution count increasing
- CloudWatch: SageMaker training time: running
- CloudWatch: GPU utilization: high
- DynamoDB: Metrics flowing in

TALKING POINTS:
- "Zero manual intervention" → fully automated
- "30-minute end-to-end" → trains faster than lunch break
- "Conditional approval" → business logic embedded
- "Model registry" → versioning and rollback capability
```

#### Part 4: Business Value & Closing (8 minutes)
```
PRESENTER: "Let me summarize what we've achieved."

SLIDE 1: Cost Savings
- Storage: 40% reduction (HTJ2K vs. standard JPEG)
- Compute: 70% reduction with Spot instances
- Operations: 100% reduction in manual MLOps work

SLIDE 2: Speed & Scale
- Retrieval latency: sub-1 second
- Pipeline automation: end-to-end in 30 minutes
- Scalability: handles unlimited concurrent uploads

SLIDE 3: Compliance & Security
- HIPAA audit trail: 7-year retention
- Encryption: AES-256 at rest and in transit
- Least-privilege IAM: cross-service role boundaries
- No PHI outside HealthImaging

SLIDE 4: Real-World Impact
- Radiologists: faster diagnoses
- Patients: quicker treatment decisions
- Operations: reduced costs and headcount
- Research: continuous model improvement

CLOSING STATEMENT:
"This is what 'Better Together' means: AWS services 
architected for healthcare. Now let's build the future 
of medical imaging."

TRANSITION:
"This concludes Module 3. Next: the Funding Roadmap 
in our final session."
```

### Demo Recovery (If Something Breaks)

```bash
# If Lambda didn't trigger
$ aws lambda invoke \
  --function-name image-ingestion-handler \
  --payload '{"Records": [{"s3": {"bucket": {"name": "'$TRAINING_BUCKET'"}, "object": {"key": "upload/demo-ct.dcm"}}}]}' \
  response.json
$ cat response.json

# If SageMaker pipeline didn't start
$ aws sagemaker start-pipeline-execution \
  --pipeline-name healthcare-imaging-training-pipeline \
  --pipeline-parameters '[{"Name": "ImageId", "Value": "demo-ct"}]'

# If CloudWatch metrics not showing
$ aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Invocations \
  --dimensions Name=FunctionName,Value=image-ingestion-handler \
  --start-time 2026-01-03T00:00:00Z \
  --end-time 2026-01-04T00:00:00Z \
  --period 300 \
  --statistics Sum

# If HealthImaging not accessible
$ aws iam get-role --role-name healthcare-imaging-lambda-role
$ aws kms describe-key --key-id alias/healthcare-imaging-key
```

---

## Troubleshooting

### Common Issues & Solutions

#### Issue 1: "AWS HealthImaging not available in region"
```
Error: BadRequestException: Service not available
Region: us-west-2

Solution:
1. HealthImaging available in: us-east-1, eu-west-1, ap-southeast-2
2. Change region in terraform.tfvars:
   aws_region = "us-east-1"
3. Re-run: terraform init && terraform apply
```

#### Issue 2: "Insufficient GPU capacity"
```
Error: InsufficientInstanceCapacity: Unable to allocate p3.2xlarge

Solution Option A (Use smaller instance):
1. terraform/modules/sagemaker/variables.tf
   Change: instance_type = "p3.8xlarge"
   To: instance_type = "p3.2xlarge" or "ml.p3.2xlarge"

Solution Option B (Request service limit increase):
1. AWS Console → Service Quotas
2. Search: "SageMaker Training"
3. Click "ml.p3.2xlarge"
4. Request quota increase: +2 instances
5. Wait 15 minutes for approval

Solution Option C (Use CPU training):
1. terraform/modules/sagemaker/training.py
   Change: instance_type = "p3.2xlarge"
   To: instance_type = "ml.m5.xlarge"
   Note: Training will take 2-3x longer (~45 minutes instead of 15)
```

#### Issue 3: "Terraform state lock"
```
Error: Error acquiring the lock: ConflictException

Solution:
1. Check if another apply is running:
   $ aws s3 ls s3://terraform-state-bucket/
2. Wait 10 minutes, then retry
3. If stuck, force unlock (CAREFUL!):
   $ terraform force-unlock <LOCK_ID>
```

#### Issue 4: "Lambda timeout"
```
Error: Task timed out after 60 seconds

Solution:
1. Increase Lambda timeout in Terraform:
   terraform/modules/lambda/variables.tf
   timeout = 300  # Increase to 5 minutes
2. Apply: terraform apply
3. Test again: aws lambda invoke ...
```

#### Issue 5: "S3 bucket access denied"
```
Error: AccessDenied: Access Denied

Solution:
1. Verify IAM permissions:
   $ aws iam get-role --role-name healthcare-imaging-lambda-role
2. Check S3 bucket policy:
   $ aws s3api get-bucket-policy --bucket <bucket-name>
3. Verify KMS key permissions:
   $ aws kms get-key-policy --key-id alias/healthcare-imaging-key --policy-name default
4. Re-apply Terraform to refresh policies:
   $ terraform apply -auto-approve
```

#### Issue 6: "DynamoDB table does not exist"
```
Error: ResourceNotFoundException: Cannot do operations on a non-existent table

Solution:
1. Check if table was created:
   $ aws dynamodb list-tables
2. If missing, re-create:
   $ terraform apply -target=aws_dynamodb_table.healthcare_imaging_metadata
3. Verify:
   $ aws dynamodb describe-table --table-name healthcare-imaging-metadata
```

#### Issue 7: "CloudWatch logs empty"
```
Error: No log entries in /aws/lambda/image-ingestion

Solution:
1. Verify CloudWatch Logs role:
   $ aws iam get-role-policy --role-name healthcare-imaging-lambda-role --policy-name cloudwatch-logs
2. Re-apply Terraform:
   $ terraform apply
3. Manually invoke Lambda:
   $ aws lambda invoke --function-name image-ingestion-handler response.json
4. Check logs again:
   $ aws logs describe-log-streams --log-group-name /aws/lambda/image-ingestion
```

### Debug Commands

```bash
# 1. Check AWS credentials
aws sts get-caller-identity

# 2. Verify region configuration
aws configure get region

# 3. List all HealthImaging datastores
aws healthimaging list-data-stores

# 4. List all SageMaker pipelines
aws sagemaker list-pipelines

# 5. Check Lambda function details
aws lambda get-function --function-name image-ingestion-handler

# 6. View Lambda recent errors
aws logs tail /aws/lambda/image-ingestion --filter-pattern ERROR

# 7. Check Terraform state
terraform state list
terraform state show aws_healthimaging_datastore.healthcare_imaging

# 8. Validate Terraform
terraform plan -json | jq '.resource_changes[] | select(.change.actions[] == "create")'

# 9. Check EventBridge rules
aws events list-rules --name-prefix healthcare

# 10. Verify S3 bucket contents
aws s3 ls s3://<bucket-name>/ --recursive

# 11. Check DynamoDB items
aws dynamodb scan --table-name healthcare-imaging-metadata --limit 10

# 12. Monitor real-time metrics
watch -n 5 'aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Invocations \
  --dimensions Name=FunctionName,Value=image-ingestion-handler \
  --start-time $(date -u -d "10 minutes ago" +%Y-%m-%dT%H:%M:%S)Z \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S)Z \
  --period 300 \
  --statistics Sum'
```

### Getting Help

1. **Check documentation**: `docs/TROUBLESHOOTING.md`
2. **View logs**: `aws logs tail /aws/lambda/<function> --follow`
3. **Check Terraform state**: `terraform state show <resource>`
4. **AWS Console**: https://console.aws.amazon.com
5. **AWS Support**: Create a support case (if enterprise)
6. **GitHub Issues**: Report bugs on GitHub

---

## Post-Deployment Steps

### 1. Update DNS Records (Production)
```bash
# Get API endpoint
API_ENDPOINT=$(terraform output -raw api_endpoint)

# Update Route53 or your DNS provider
aws route53 change-resource-record-sets \
  --hosted-zone-id <ZONE_ID> \
  --change-batch file://dns-changes.json
```

### 2. Configure Email Notifications
```bash
# Subscribe to SNS topics
aws sns subscribe \
  --topic-arn arn:aws:sns:us-east-1:ACCOUNT_ID:healthcare-imaging-alerts \
  --protocol email \
  --notification-endpoint your-email@example.com
```

### 3. Set Up CloudWatch Alarms
```bash
# Run alarm setup script
python scripts/monitoring/setup-alarms.py
```

### 4. Enable Audit Logging
```bash
# Enable CloudTrail
aws cloudtrail create-trail \
  --name healthcare-imaging-audit \
  --s3-bucket-name <audit-bucket>

# Enable S3 access logging
aws s3api put-bucket-logging \
  --bucket <training-bucket> \
  --bucket-logging-status file://logging-config.json
```

### 5. Configure Backup & Recovery
```bash
# Enable DynamoDB point-in-time recovery
aws dynamodb update-continuous-backups \
  --table-name healthcare-imaging-metadata \
  --point-in-time-recovery-specification PointInTimeRecoveryEnabled=true
```

---

## Cost Optimization

### Development (Minimal Cost)
```bash
# Use on-demand for dev/test
terraform apply -var="environment=dev"

# Estimated: ~$434/month
```

### Production (Optimized Cost)
```bash
# Use reserved capacity + spot
terraform apply -var="environment=prod"

# Estimated: ~$2,454/month (with optimizations)
```

### Further Savings
1. **Spot Instances**: +70% savings on training
2. **Reserved Capacity**: +35% savings on compute
3. **S3 Intelligent-Tiering**: +20% storage savings
4. **CloudFront Caching**: +60% bandwidth savings

---

## Next Steps

1. ✅ **Complete deployment** (you are here)
2. ⏭️ **Configure CI/CD** → `.github/workflows/deploy-prod.yml`
3. ⏭️ **Integrate with FHIR system** → Module 2 output
4. ⏭️ **Set up alerts** → CloudWatch + SNS
5. ⏭️ **Plan security review** → HIPAA audit
6. ⏭️ **Scale to production** → Multi-region setup

---

## Support

**Email**: healthcare-support@example.com  
**Slack**: #healthcare-mlops  
**GitHub**: https://github.com/your-org/healthcare-imaging-mlops  
**AWS Support**: AWS Support case (Enterprise)

---

**Last Updated**: January 3, 2026  
**Maintainer**: Cloud Assembly (AWS Advanced Partner)

**Ready for demo?** See [Module 3 Demo Script](#workshop-demo) above.
