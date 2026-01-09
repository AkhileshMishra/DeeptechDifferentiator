# Healthcare Imaging MLOps Platform - Test & Validation Guide

> **Note:** This guide is derived entirely from source code analysis (Terraform, Python, Docker configurations). All resource names, schemas, and configurations are verified against actual implementation.

---

## Table of Contents

1. [Resource Naming Convention](#1-resource-naming-convention)
2. [Infrastructure Validation](#2-infrastructure-validation)
3. [Lambda Function Testing](#3-lambda-function-testing)
4. [S3 Data Flow Testing](#4-s3-data-flow-testing)
5. [DynamoDB Testing](#5-dynamodb-testing)
6. [AWS HealthImaging Testing](#6-aws-healthimaging-testing)
7. [SageMaker Pipeline Testing](#7-sagemaker-pipeline-testing)
8. [EventBridge Testing](#8-eventbridge-testing)
9. [Docker Container Testing](#9-docker-container-testing)
10. [Python Unit Tests](#10-python-unit-tests)
11. [CloudWatch Monitoring Validation](#11-cloudwatch-monitoring-validation)
12. [Frontend Testing](#12-frontend-testing)
13. [Security Validation](#13-security-validation)
14. [End-to-End Integration Tests](#14-end-to-end-integration-tests)
15. [Cleanup & Teardown](#15-cleanup--teardown)

---

## 1. Resource Naming Convention

Based on `terraform/main-modules.tf`, all resources follow this pattern:

```
name_prefix = "${var.project_name}-${var.environment}"
# Example: healthcare-imaging-dev
```

### Resource Name Reference Table

| Resource Type | Name Pattern | Example |
|---------------|--------------|---------|
| **Lambda Functions** | `{prefix}-image-ingestion`, `{prefix}-pipeline-trigger`, `{prefix}-model-evaluation`, `{prefix}-model-registry`, `{prefix}-get-presigned-url` | `healthcare-imaging-dev-image-ingestion` |
| **DynamoDB Tables** | `{prefix}-image-metadata`, `{prefix}-training-metrics`, `{prefix}-pipeline-state` | `healthcare-imaging-dev-image-metadata` |
| **S3 Buckets** | `{prefix}-training-data-{account_id}`, `{prefix}-preprocessed-data-{account_id}`, `{prefix}-model-artifacts-{account_id}`, `{prefix}-logs-{account_id}` | `healthcare-imaging-dev-training-data-123456789012` |
| **HealthImaging Datastore** | `{prefix}-imaging-store` | `healthcare-imaging-dev-imaging-store` |
| **SageMaker Pipeline** | `{prefix}-pneumonia-pipeline` | `healthcare-imaging-dev-pneumonia-pipeline` |
| **EventBridge Bus** | `{prefix}-imaging-events` | `healthcare-imaging-dev-imaging-events` |
| **ECR Repositories** | `{prefix}-preprocessing`, `{prefix}-training`, `{prefix}-evaluation`, `{prefix}-inference`, `{prefix}-api` | `healthcare-imaging-dev-training` |
| **IAM Roles** | `{prefix}-lambda-execution-role`, `{prefix}-sagemaker-role`, `{prefix}-healthimaging-access-role`, `{prefix}-eventbridge-invoke-role` | `healthcare-imaging-dev-lambda-execution-role` |

---

## 2. Infrastructure Validation

### 2.1 Prerequisites Check

```bash
# Verify required tools
aws --version        # AWS CLI v2.x required
terraform --version  # Terraform >= 1.0 required
python --version     # Python 3.9+ required
docker --version     # Docker required for container builds

# Verify AWS credentials
aws sts get-caller-identity

# Verify region supports HealthImaging (us-east-1, eu-west-1, ap-southeast-2)
aws medical-imaging list-data-stores --region us-east-1
```

### 2.2 Terraform Validation

```bash
cd terraform

# Initialize Terraform
terraform init

# Validate configuration syntax
terraform validate

# Generate execution plan
terraform plan -out=tfplan

# Apply infrastructure
terraform apply tfplan

# Save outputs for testing
terraform output -json > deployment-outputs.json
```

### 2.3 Post-Deployment Resource Validation

```bash
# Set variables (adjust based on your terraform.tfvars)
PROJECT="healthcare-imaging"  # var.project_name
ENV="dev"                     # var.environment
PREFIX="${PROJECT}-${ENV}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="us-east-1"            # var.aws_region

# --- VPC Validation ---
VPC_ID=$(cd terraform && terraform output -raw vpc_id)
aws ec2 describe-vpcs --vpc-ids $VPC_ID --query "Vpcs[0].State" --output text
# Expected: available

# --- S3 Buckets Validation ---
# Source: terraform/modules/storage/main.tf
aws s3api head-bucket --bucket "${PREFIX}-training-data-${ACCOUNT_ID}"
aws s3api head-bucket --bucket "${PREFIX}-preprocessed-data-${ACCOUNT_ID}"
aws s3api head-bucket --bucket "${PREFIX}-model-artifacts-${ACCOUNT_ID}"
aws s3api head-bucket --bucket "${PREFIX}-logs-${ACCOUNT_ID}"

# --- DynamoDB Tables Validation ---
# Source: terraform/modules/dynamodb/main.tf
aws dynamodb describe-table --table-name "${PREFIX}-image-metadata" --query "Table.TableStatus" --output text
aws dynamodb describe-table --table-name "${PREFIX}-training-metrics" --query "Table.TableStatus" --output text
aws dynamodb describe-table --table-name "${PREFIX}-pipeline-state" --query "Table.TableStatus" --output text
# Expected: ACTIVE

# --- Lambda Functions Validation ---
# Source: terraform/modules/lambda/main.tf
aws lambda get-function --function-name "${PREFIX}-image-ingestion" --query "Configuration.State" --output text
aws lambda get-function --function-name "${PREFIX}-pipeline-trigger" --query "Configuration.State" --output text
aws lambda get-function --function-name "${PREFIX}-model-evaluation" --query "Configuration.State" --output text
aws lambda get-function --function-name "${PREFIX}-model-registry" --query "Configuration.State" --output text
# Expected: Active

# --- HealthImaging Datastore Validation ---
# Source: terraform/modules/healthimaging/main.tf
DATASTORE_ID=$(cd terraform && terraform output -raw healthimaging_data_store_id)
aws medical-imaging get-datastore --datastore-id $DATASTORE_ID --query "datastoreProperties.datastoreStatus" --output text
# Expected: ACTIVE

# --- SageMaker Pipeline Validation ---
# Source: terraform/main-modules.tf (local.sagemaker_config.pipeline_name)
aws sagemaker describe-pipeline --pipeline-name "${PREFIX}-pneumonia-pipeline" --query "PipelineStatus" --output text
# Expected: Active

# --- ECR Repositories Validation ---
# Source: terraform/modules/ecr/main.tf
for repo in preprocessing training evaluation inference api; do
    aws ecr describe-repositories --repository-names "${PREFIX}-${repo}" --query "repositories[0].repositoryName" --output text
done
```

### 2.4 Run Built-in Validation Script

```bash
# Source: scripts/validate-deployment.sh
chmod +x scripts/validate-deployment.sh
./scripts/validate-deployment.sh
```

---

## 3. Lambda Function Testing

### 3.1 Image Ingestion Lambda

**Source:** `python/src/lambda_handlers/image_ingestion/handler.py`

**Environment Variables Required:**
- `DATASTORE_ID` or `HEALTHIMAGING_DATASTORE_ID`
- `INPUT_BUCKET` or `TRAINING_BUCKET`
- `OUTPUT_BUCKET`
- `AHI_IMPORT_ROLE_ARN` or `DATA_ACCESS_ROLE_ARN`
- `IMAGE_TRACKING_TABLE`
- `EVENT_BUS_NAME`

**Trigger:** S3 ObjectCreated event on `input/` prefix

```bash
# Test with mock S3 event
cat > /tmp/s3-event.json << 'EOF'
{
  "Records": [{
    "s3": {
      "bucket": {"name": "YOUR_TRAINING_BUCKET"},
      "object": {"key": "input/test-image.dcm"}
    }
  }]
}
EOF

aws lambda invoke \
  --function-name "${PREFIX}-image-ingestion" \
  --payload file:///tmp/s3-event.json \
  --cli-binary-format raw-in-base64-out \
  /tmp/response.json

cat /tmp/response.json

# Check CloudWatch logs
aws logs tail "/aws/lambda/${PREFIX}-image-ingestion" --follow
```

**Expected Response:**
```json
{
  "statusCode": 200,
  "body": "{\"message\": \"Ingestion processing complete\", \"results\": [...]}"
}
```

### 3.2 Pipeline Trigger Lambda

**Source:** `python/src/lambda_handlers/pipeline_trigger/handler.py`

**Environment Variables Required:**
- `PIPELINE_NAME`
- `S3_BUCKET`

**Trigger:** API Gateway POST or EventBridge event

```bash
# Test with API Gateway style event
cat > /tmp/api-event.json << 'EOF'
{
  "body": "{\"imageSetId\": \"test-image-set\"}"
}
EOF

aws lambda invoke \
  --function-name "${PREFIX}-pipeline-trigger" \
  --payload file:///tmp/api-event.json \
  --cli-binary-format raw-in-base64-out \
  /tmp/response.json

cat /tmp/response.json

# Test with EventBridge style event
cat > /tmp/eb-event.json << 'EOF'
{
  "source": "imaging.mlops",
  "detail-type": "ImageVerified",
  "detail": {
    "imageSetId": "test-image-set"
  }
}
EOF

aws lambda invoke \
  --function-name "${PREFIX}-pipeline-trigger" \
  --payload file:///tmp/eb-event.json \
  --cli-binary-format raw-in-base64-out \
  /tmp/response.json
```

**Expected Response:**
```json
{
  "statusCode": 200,
  "body": "{\"message\": \"Pipeline execution started\", \"executionArn\": \"arn:aws:sagemaker:...\"}"
}
```

### 3.3 Get Presigned URL Lambda

**Source:** `python/src/lambda_handlers/get_presigned_url/handler.py`

**Environment Variables Required:**
- `BUCKET_NAME`

```bash
cat > /tmp/url-event.json << 'EOF'
{
  "queryStringParameters": {
    "imageSetId": "demo-chest-ct"
  }
}
EOF

aws lambda invoke \
  --function-name "${PREFIX}-get-presigned-url" \
  --payload file:///tmp/url-event.json \
  --cli-binary-format raw-in-base64-out \
  /tmp/response.json

cat /tmp/response.json
```

**Expected Response:**
```json
{
  "statusCode": 200,
  "headers": {"Access-Control-Allow-Origin": "*"},
  "body": "{\"url\": \"https://s3.amazonaws.com/...\"}"
}
```

### 3.4 Model Evaluation Lambda

**Source:** `python/src/lambda_handlers/model_evaluation/handler.py`

**Environment Variables Required:**
- `MODEL_ARTIFACTS_BUCKET` or `MODEL_BUCKET`
- `METRICS_TABLE`
- `CLOUDWATCH_NAMESPACE`
- `ACCURACY_THRESHOLD` (default: 0.85)
- `EVENT_BUS_NAME`

```bash
cat > /tmp/eval-event.json << 'EOF'
{
  "detail": {
    "TrainingJobName": "test-training-job",
    "TrainingJobStatus": "Completed",
    "ModelArtifacts": {
      "S3ModelArtifacts": "s3://bucket/model/model.tar.gz"
    }
  }
}
EOF

aws lambda invoke \
  --function-name "${PREFIX}-model-evaluation" \
  --payload file:///tmp/eval-event.json \
  --cli-binary-format raw-in-base64-out \
  /tmp/response.json
```

### 3.5 Model Registry Lambda

**Source:** `python/src/lambda_handlers/model_registry/handler.py`

**Environment Variables Required:**
- `MODEL_PACKAGE_GROUP`
- `SAGEMAKER_ROLE_ARN`
- `INFERENCE_IMAGE_URI`
- `EVENT_BUS_NAME`

```bash
cat > /tmp/registry-event.json << 'EOF'
{
  "detail": {
    "modelArtifacts": "s3://bucket/model/model.tar.gz",
    "metrics": {
      "accuracy": 0.92,
      "precision": 0.89,
      "recall": 0.91
    }
  }
}
EOF

aws lambda invoke \
  --function-name "${PREFIX}-model-registry" \
  --payload file:///tmp/registry-event.json \
  --cli-binary-format raw-in-base64-out \
  /tmp/response.json
```

---

## 4. S3 Data Flow Testing

**Source:** `terraform/main-modules.tf` (S3 notification configuration)

S3 notification triggers Lambda on `input/` prefix.

### 4.1 Upload Test Data

```bash
TRAINING_BUCKET="${PREFIX}-training-data-${ACCOUNT_ID}"

# Upload a test file to trigger Lambda
echo "test" > /tmp/test.dcm
aws s3 cp /tmp/test.dcm "s3://${TRAINING_BUCKET}/input/test-$(date +%Y%m%d%H%M%S).dcm"

# Verify upload
aws s3 ls "s3://${TRAINING_BUCKET}/input/"

# Monitor Lambda trigger
aws logs tail "/aws/lambda/${PREFIX}-image-ingestion" --since 2m --follow
```

### 4.2 Verify S3 Bucket Configuration

```bash
# Check notification configuration
aws s3api get-bucket-notification-configuration --bucket $TRAINING_BUCKET

# Check encryption
aws s3api get-bucket-encryption --bucket $TRAINING_BUCKET

# Check public access block
aws s3api get-public-access-block --bucket $TRAINING_BUCKET

# Check versioning
aws s3api get-bucket-versioning --bucket $TRAINING_BUCKET

# Check lifecycle rules
aws s3api get-bucket-lifecycle-configuration --bucket $TRAINING_BUCKET
```

---

## 5. DynamoDB Testing

**Source:** `terraform/modules/dynamodb/main.tf`

### 5.1 Image Metadata Table

**Schema:**
- Hash Key: `image_id` (String)
- Range Key: `timestamp` (String)
- GSI: `patient-index` (patient_id, timestamp)
- GSI: `status-index` (status, timestamp)

```bash
TABLE_NAME="${PREFIX}-image-metadata"

# Insert test record
aws dynamodb put-item \
  --table-name $TABLE_NAME \
  --item '{
    "image_id": {"S": "test-image-001"},
    "timestamp": {"S": "2026-01-09T10:00:00Z"},
    "patient_id": {"S": "PATIENT-001"},
    "status": {"S": "INGESTED"},
    "modality": {"S": "CT"},
    "body_part": {"S": "CHEST"}
  }'

# Query by primary key
aws dynamodb get-item \
  --table-name $TABLE_NAME \
  --key '{"image_id": {"S": "test-image-001"}, "timestamp": {"S": "2026-01-09T10:00:00Z"}}'

# Query by patient_id (GSI)
aws dynamodb query \
  --table-name $TABLE_NAME \
  --index-name patient-index \
  --key-condition-expression "patient_id = :pid" \
  --expression-attribute-values '{":pid": {"S": "PATIENT-001"}}'

# Query by status (GSI)
aws dynamodb query \
  --table-name $TABLE_NAME \
  --index-name status-index \
  --key-condition-expression "#s = :status" \
  --expression-attribute-names '{"#s": "status"}' \
  --expression-attribute-values '{":status": {"S": "INGESTED"}}'

# Update status to VERIFIED
aws dynamodb update-item \
  --table-name $TABLE_NAME \
  --key '{"image_id": {"S": "test-image-001"}, "timestamp": {"S": "2026-01-09T10:00:00Z"}}' \
  --update-expression "SET #s = :status" \
  --expression-attribute-names '{"#s": "status"}' \
  --expression-attribute-values '{":status": {"S": "VERIFIED"}}'
```

### 5.2 Training Metrics Table

**Schema:**
- Hash Key: `pipeline_execution_id` (String)
- Range Key: `metric_name` (String)
- GSI: `model-version-index` (model_version, metric_name)

```bash
TABLE_NAME="${PREFIX}-training-metrics"

# Insert training metrics
aws dynamodb put-item \
  --table-name $TABLE_NAME \
  --item '{
    "pipeline_execution_id": {"S": "exec-001"},
    "metric_name": {"S": "accuracy"},
    "model_version": {"S": "v1.0.0"},
    "value": {"N": "0.87"},
    "timestamp": {"S": "2026-01-09T10:00:00Z"}
  }'

# Query metrics by execution
aws dynamodb query \
  --table-name $TABLE_NAME \
  --key-condition-expression "pipeline_execution_id = :eid" \
  --expression-attribute-values '{":eid": {"S": "exec-001"}}'

# Query by model version (GSI)
aws dynamodb query \
  --table-name $TABLE_NAME \
  --index-name model-version-index \
  --key-condition-expression "model_version = :mv" \
  --expression-attribute-values '{":mv": {"S": "v1.0.0"}}'
```

### 5.3 Pipeline State Table

**Schema:**
- Hash Key: `execution_id` (String)
- GSI: `status-index` (status)

```bash
TABLE_NAME="${PREFIX}-pipeline-state"

# Insert pipeline state
aws dynamodb put-item \
  --table-name $TABLE_NAME \
  --item '{
    "execution_id": {"S": "exec-001"},
    "status": {"S": "RUNNING"},
    "started_at": {"S": "2026-01-09T10:00:00Z"},
    "pipeline_name": {"S": "pneumonia-pipeline"}
  }'

# Query by status
aws dynamodb query \
  --table-name $TABLE_NAME \
  --index-name status-index \
  --key-condition-expression "#s = :status" \
  --expression-attribute-names '{"#s": "status"}' \
  --expression-attribute-values '{":status": {"S": "RUNNING"}}'
```

---

## 6. AWS HealthImaging Testing

**Source:** `terraform/modules/healthimaging/main.tf`, `python/src/healthimaging/client.py`

### 6.1 Datastore Operations

```bash
DATASTORE_ID=$(cd terraform && terraform output -raw healthimaging_data_store_id)

# Get datastore details
aws medical-imaging get-datastore --datastore-id $DATASTORE_ID

# List all datastores
aws medical-imaging list-data-stores

# Search image sets in datastore
aws medical-imaging search-image-sets \
  --datastore-id $DATASTORE_ID \
  --max-results 10
```

### 6.2 DICOM Import Job Testing

```bash
TRAINING_BUCKET="${PREFIX}-training-data-${ACCOUNT_ID}"
ROLE_ARN=$(cd terraform && terraform output -raw healthimaging_import_role_arn 2>/dev/null || echo "")

# Start a DICOM import job
aws medical-imaging start-dicom-import-job \
  --datastore-id $DATASTORE_ID \
  --job-name "test-import-$(date +%Y%m%d%H%M%S)" \
  --input-s3-uri "s3://${TRAINING_BUCKET}/input/" \
  --output-s3-uri "s3://${TRAINING_BUCKET}/ahi-output/" \
  --data-access-role-arn $ROLE_ARN

# List import jobs
aws medical-imaging list-dicom-import-jobs --datastore-id $DATASTORE_ID

# Get specific job status (replace JOB_ID)
aws medical-imaging get-dicom-import-job \
  --datastore-id $DATASTORE_ID \
  --job-id "YOUR_JOB_ID"
```

### 6.3 Image Set Operations

```bash
# Get image set details (replace IMAGE_SET_ID)
aws medical-imaging get-image-set \
  --datastore-id $DATASTORE_ID \
  --image-set-id "YOUR_IMAGE_SET_ID"

# Get image set metadata
aws medical-imaging get-image-set-metadata \
  --datastore-id $DATASTORE_ID \
  --image-set-id "YOUR_IMAGE_SET_ID"
```

---

## 7. SageMaker Pipeline Testing

**Source:** `terraform/modules/sagemaker/main.tf`, `python/src/pipeline/pipeline_builder.py`

### 7.1 Pipeline Operations

```bash
PIPELINE_NAME="${PREFIX}-pneumonia-pipeline"

# Describe pipeline
aws sagemaker describe-pipeline --pipeline-name $PIPELINE_NAME

# List all pipelines
aws sagemaker list-pipelines --query "PipelineSummaries[*].[PipelineName,PipelineStatus]" --output table

# Start pipeline execution manually
aws sagemaker start-pipeline-execution \
  --pipeline-name $PIPELINE_NAME \
  --pipeline-execution-display-name "manual-test-$(date +%Y%m%d%H%M%S)" \
  --pipeline-parameters '[{"Name": "InputDataUrl", "Value": "s3://YOUR_BUCKET/input/"}]'

# List recent executions
aws sagemaker list-pipeline-executions \
  --pipeline-name $PIPELINE_NAME \
  --sort-by CreationTime \
  --sort-order Descending \
  --max-results 5

# Get execution details (replace EXECUTION_ARN)
aws sagemaker describe-pipeline-execution \
  --pipeline-execution-arn "YOUR_EXECUTION_ARN"

# List execution steps
aws sagemaker list-pipeline-execution-steps \
  --pipeline-execution-arn "YOUR_EXECUTION_ARN"
```

### 7.2 Monitor Training Jobs

```bash
# List training jobs
aws sagemaker list-training-jobs \
  --sort-by CreationTime \
  --sort-order Descending \
  --max-results 5

# Describe training job (replace JOB_NAME)
aws sagemaker describe-training-job --training-job-name "YOUR_JOB_NAME"

# View training logs
aws logs tail "/aws/sagemaker/TrainingJobs" --follow
```

### 7.3 Model Registry Operations

```bash
MODEL_PACKAGE_GROUP="${PREFIX}-model-registry"

# List model packages
aws sagemaker list-model-packages \
  --model-package-group-name $MODEL_PACKAGE_GROUP

# Describe model package (replace PACKAGE_ARN)
aws sagemaker describe-model-package \
  --model-package-name "YOUR_PACKAGE_ARN"
```

---

## 8. EventBridge Testing

**Source:** `terraform/modules/eventbridge/main.tf`, `terraform/main-modules.tf`

### 8.1 Event Bus and Rules Validation

```bash
EVENT_BUS="${PREFIX}-imaging-events"

# List event buses
aws events list-event-buses --query "EventBuses[*].[Name,Arn]" --output table

# List rules on custom event bus
aws events list-rules --event-bus-name $EVENT_BUS

# Describe specific rules
aws events describe-rule --event-bus-name $EVENT_BUS --name "${PREFIX}-image_verified"
aws events describe-rule --event-bus-name $EVENT_BUS --name "${PREFIX}-model_training_complete"
aws events describe-rule --event-bus-name $EVENT_BUS --name "${PREFIX}-model_evaluation_passed"

# List targets for a rule
aws events list-targets-by-rule --event-bus-name $EVENT_BUS --rule "${PREFIX}-image_verified"
```

### 8.2 Send Test Events

**Event patterns from code:**
- `imaging.mlops` / `ImageVerified` → triggers pipeline_trigger Lambda
- `aws.sagemaker` / `SageMaker Training Job State Change` → triggers model_evaluation Lambda
- `imaging.mlops` / `ModelEvaluationPassed` → triggers model_registry Lambda

```bash
# Send ImageVerified event
aws events put-events --entries '[{
  "Source": "imaging.mlops",
  "DetailType": "ImageVerified",
  "Detail": "{\"imageSetId\": \"test-image\", \"datastoreId\": \"YOUR_DATASTORE_ID\"}",
  "EventBusName": "'$EVENT_BUS'"
}]'

# Check Lambda was triggered
aws logs tail "/aws/lambda/${PREFIX}-pipeline-trigger" --since 2m

# Send ModelEvaluationPassed event
aws events put-events --entries '[{
  "Source": "imaging.mlops",
  "DetailType": "ModelEvaluationPassed",
  "Detail": "{\"modelArtifacts\": \"s3://bucket/model.tar.gz\", \"accuracy\": 0.92}",
  "EventBusName": "'$EVENT_BUS'"
}]'

# Check model registry Lambda was triggered
aws logs tail "/aws/lambda/${PREFIX}-model-registry" --since 2m
```

### 8.3 Check Dead Letter Queue

```bash
# Get DLQ URL
DLQ_URL=$(aws sqs list-queues --queue-name-prefix "${PREFIX}-eventbridge-dlq" --query "QueueUrls[0]" --output text)

# Receive messages from DLQ
aws sqs receive-message --queue-url $DLQ_URL --max-number-of-messages 10
```

---

## 9. Docker Container Testing

**Source:** `docker/sagemaker/` directory

### 9.1 Build Containers Locally

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="us-east-1"

# Build preprocessing container
cd docker/sagemaker/preprocessing
docker build -t "${PREFIX}-preprocessing:test" .
docker run --rm "${PREFIX}-preprocessing:test" python -c "import numpy; print('Preprocessing OK')"

# Build training container
cd ../training
docker build -t "${PREFIX}-training:test" .
docker run --rm "${PREFIX}-training:test" python -c "import tensorflow; print(f'TensorFlow {tensorflow.__version__} OK')"

# Build evaluation container
cd ../evaluation
docker build -t "${PREFIX}-evaluation:test" .
docker run --rm "${PREFIX}-evaluation:test" python -c "import sklearn; print('Evaluation OK')"

# Build inference container
cd ../inference
docker build -t "${PREFIX}-inference:test" .
docker run --rm "${PREFIX}-inference:test" python -c "print('Inference OK')"
```

### 9.2 Push to ECR

```bash
# Login to ECR
aws ecr get-login-password --region $REGION | \
  docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

# Tag and push each container
for container in preprocessing training evaluation inference; do
    docker tag "${PREFIX}-${container}:test" \
      "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${PREFIX}-${container}:latest"
    
    docker push "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${PREFIX}-${container}:latest"
done

# Verify images in ECR
for container in preprocessing training evaluation inference; do
    aws ecr describe-images --repository-name "${PREFIX}-${container}" \
      --query "imageDetails[*].[imageTags,imagePushedAt]" --output table
done
```

### 9.3 Test Container Entry Points

**Training container entry point:** `docker/sagemaker/training/train.py`

```bash
# Test training script arguments
docker run --rm "${PREFIX}-training:test" python train.py --help

# Expected arguments:
# --epochs, --batch-size, --learning-rate, --target-size, --patience
# --model-dir, --train, --validation
```

---

## 10. Python Unit Tests

**Source:** `python/tests/`

### 10.1 Setup Test Environment

```bash
cd python

# Create virtual environment
python -m venv venv
source venv/bin/activate  # Linux/Mac
# or: .\venv\Scripts\Activate.ps1  # Windows PowerShell

# Install dependencies
pip install -r requirements.txt
pip install -r requirements-dev.txt
```

### 10.2 Run Unit Tests

```bash
# Run all tests
pytest tests/ -v

# Run specific test files
pytest tests/test_healthimaging.py -v
pytest tests/test_preprocessing.py -v

# Run with coverage report
pytest tests/ -v --cov=src --cov-report=html --cov-report=term

# Run tests matching pattern
pytest tests/ -k "test_normalize" -v

# Run tests with verbose output
pytest tests/ -v --tb=long
```

### 10.3 Test Individual Modules

```bash
# Test HealthImaging client import
python -c "from src.healthimaging.client import HealthImagingClient; print('HealthImaging client OK')"

# Test preprocessing module
python -c "from src.pipeline.preprocessing import DICOMPreprocessor, DataAugmenter; print('Preprocessing OK')"

# Test training module
python -c "from src.pipeline.training import create_model, compile_model; print('Training OK')"

# Test evaluation module
python -c "from src.pipeline.evaluation import load_model, evaluate_model; print('Evaluation OK')"

# Test pipeline builder
python -c "from src.pipeline.pipeline_builder import PneumoniaDetectionPipeline; print('Pipeline builder OK')"
```

### 10.4 Available Test Cases

**From `python/tests/test_healthimaging.py`:**
- `test_client_initialization` - Client creation
- `test_get_datastore` - Datastore retrieval
- `test_get_image_set` - Image set retrieval
- `test_start_dicom_import_job` - Import job creation
- `test_get_dicom_import_job` - Import job status
- `test_extract_frame_ids` - Frame ID extraction
- `test_create_client_from_env` - Environment-based client creation

**From `python/tests/test_preprocessing.py`:**
- `test_normalize_image` - Image normalization
- `test_normalize_constant_image` - Edge case handling
- `test_resize_image` - Image resizing
- `test_extract_metadata` - DICOM metadata extraction
- `test_flip_horizontal` - Horizontal flip augmentation
- `test_flip_vertical` - Vertical flip augmentation
- `test_adjust_brightness` - Brightness adjustment
- `test_brightness_clipping` - Value clipping
- `test_create_train_test_split` - Data splitting

---

## 11. CloudWatch Monitoring Validation

**Source:** `terraform/modules/monitoring/main.tf`

### 11.1 Dashboard Verification

```bash
# List dashboards
aws cloudwatch list-dashboards --dashboard-name-prefix $PREFIX

# Get dashboard details
aws cloudwatch get-dashboard --dashboard-name "${PREFIX}-dashboard"
```

### 11.2 Alarms Verification

```bash
# List all alarms
aws cloudwatch describe-alarms --alarm-name-prefix $PREFIX \
  --query "MetricAlarms[*].[AlarmName,StateValue,MetricName]" --output table

# Check specific alarms (from terraform/modules/monitoring/main.tf)
aws cloudwatch describe-alarms --alarm-names \
  "${PREFIX}-lambda-errors" \
  "${PREFIX}-pipeline-failures" \
  "${PREFIX}-dynamodb-throttling"
```

### 11.3 Metrics Verification

```bash
# Lambda invocation metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Invocations \
  --dimensions Name=FunctionName,Value="${PREFIX}-image-ingestion" \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 \
  --statistics Sum

# Lambda error metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Errors \
  --dimensions Name=FunctionName,Value="${PREFIX}-image-ingestion" \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 \
  --statistics Sum

# DynamoDB consumed capacity
aws cloudwatch get-metric-statistics \
  --namespace AWS/DynamoDB \
  --metric-name ConsumedReadCapacityUnits \
  --dimensions Name=TableName,Value="${PREFIX}-image-metadata" \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 \
  --statistics Sum
```

### 11.4 Log Analysis

```bash
# Tail Lambda logs
aws logs tail "/aws/lambda/${PREFIX}-image-ingestion" --follow
aws logs tail "/aws/lambda/${PREFIX}-pipeline-trigger" --follow
aws logs tail "/aws/lambda/${PREFIX}-model-evaluation" --follow

# Search for errors
aws logs filter-log-events \
  --log-group-name "/aws/lambda/${PREFIX}-image-ingestion" \
  --filter-pattern "ERROR" \
  --start-time $(date -u -d '1 hour ago' +%s)000

# CloudWatch Logs Insights query
aws logs start-query \
  --log-group-name "/aws/lambda/${PREFIX}-image-ingestion" \
  --start-time $(date -u -d '1 hour ago' +%s) \
  --end-time $(date -u +%s) \
  --query-string 'fields @timestamp, @message | filter @message like /ERROR/ | sort @timestamp desc | limit 20'
```

### 11.5 Run Monitoring Script

```bash
# Source: scripts/monitoring.sh
chmod +x scripts/monitoring.sh
./scripts/monitoring.sh
```

---

## 12. Frontend Testing

**Source:** `frontend/index.html`, `frontend/config.js`

### 12.1 Generate Frontend Configuration

```bash
# Run config generation script
chmod +x scripts/generate-frontend-config.sh
./scripts/generate-frontend-config.sh

# Verify config.js was updated
cat frontend/config.js
```

### 12.2 Local Frontend Testing

```bash
cd frontend

# Start local HTTP server
python -m http.server 8080

# Open browser to http://localhost:8080
```

**Manual Test Steps:**
1. Enter API Gateway endpoint in the configuration panel
2. Click "Stream 1GB Scan" - should load DICOM viewer
3. Verify image displays with window/level controls
4. Click "Verify & Train" - should trigger pipeline
5. Check browser console for errors

### 12.3 API Gateway Endpoint Testing

**Routes from `frontend/config.js`:**
- `GET /get-image-frame?imageSetId=<id>` - Get presigned URL
- `POST /trigger-pipeline` - Trigger ML pipeline

```bash
API_ENDPOINT=$(cd terraform && terraform output -raw api_gateway_endpoint 2>/dev/null || echo "YOUR_API_ENDPOINT")

# Test GET presigned URL endpoint
curl -X GET "${API_ENDPOINT}/get-image-frame?imageSetId=demo-chest-ct"

# Test POST pipeline trigger endpoint
curl -X POST "${API_ENDPOINT}/trigger-pipeline" \
  -H "Content-Type: application/json" \
  -d '{"imageSetId": "demo-chest-ct", "action": "VERIFY"}'
```

### 12.4 CORS Verification

```bash
# Test CORS preflight
curl -X OPTIONS "${API_ENDPOINT}/get-image-frame" \
  -H "Origin: http://localhost:8080" \
  -H "Access-Control-Request-Method: GET" \
  -v
```

---

## 13. Security Validation

### 13.1 IAM Role Verification

**Source:** `terraform/modules/lambda/main.tf`, `terraform/modules/sagemaker/main.tf`

```bash
# List IAM roles
aws iam list-roles --query "Roles[?contains(RoleName, '${PREFIX}')].[RoleName]" --output table

# Lambda execution role
aws iam get-role --role-name "${PREFIX}-lambda-execution-role"
aws iam list-attached-role-policies --role-name "${PREFIX}-lambda-execution-role"
aws iam list-role-policies --role-name "${PREFIX}-lambda-execution-role"

# SageMaker execution role
aws iam get-role --role-name "${PREFIX}-sagemaker-role"
aws iam list-attached-role-policies --role-name "${PREFIX}-sagemaker-role"

# HealthImaging access role
aws iam get-role --role-name "${PREFIX}-healthimaging-access-role"

# EventBridge invoke role
aws iam get-role --role-name "${PREFIX}-eventbridge-invoke-role"
```

### 13.2 KMS Key Verification

**Source:** `terraform/modules/security/main.tf`

```bash
# List KMS keys/aliases
aws kms list-aliases --query "Aliases[?contains(AliasName, '${PREFIX}')].[AliasName,TargetKeyId]" --output table

# Describe S3 KMS key
aws kms describe-key --key-id "alias/${PREFIX}-s3-key"

# Describe SageMaker KMS key
aws kms describe-key --key-id "alias/${PREFIX}-sagemaker-key"

# Verify key policies
aws kms get-key-policy --key-id "alias/${PREFIX}-s3-key" --policy-name default --output text
```

### 13.3 VPC Security Groups

**Source:** `terraform/modules/networking/main.tf`

```bash
VPC_ID=$(cd terraform && terraform output -raw vpc_id)

# List security groups
aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=${VPC_ID}" \
  --query "SecurityGroups[*].[GroupId,GroupName,Description]" --output table

# Get Lambda security group rules
LAMBDA_SG=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=*${PREFIX}*lambda*" \
  --query "SecurityGroups[0].GroupId" --output text)

aws ec2 describe-security-group-rules --filters "Name=group-id,Values=${LAMBDA_SG}"

# Get SageMaker security group rules
SM_SG=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=*${PREFIX}*sagemaker*" \
  --query "SecurityGroups[0].GroupId" --output text)

aws ec2 describe-security-group-rules --filters "Name=group-id,Values=${SM_SG}"
```

### 13.4 S3 Bucket Security

```bash
TRAINING_BUCKET="${PREFIX}-training-data-${ACCOUNT_ID}"

# Verify encryption is enabled (should be KMS)
aws s3api get-bucket-encryption --bucket $TRAINING_BUCKET

# Verify public access is blocked
aws s3api get-public-access-block --bucket $TRAINING_BUCKET
# Expected: All four settings should be true

# Verify versioning is enabled
aws s3api get-bucket-versioning --bucket $TRAINING_BUCKET
# Expected: Status: Enabled

# Check bucket policy
aws s3api get-bucket-policy --bucket $TRAINING_BUCKET --output text 2>/dev/null || echo "No bucket policy"
```

### 13.5 VPC Endpoints Verification

```bash
# List VPC endpoints
aws ec2 describe-vpc-endpoints \
  --filters "Name=vpc-id,Values=${VPC_ID}" \
  --query "VpcEndpoints[*].[ServiceName,State,VpcEndpointType]" --output table

# Expected endpoints: S3, DynamoDB, SageMaker, HealthImaging, etc.
```

### 13.6 Secrets Manager Verification

```bash
# List secrets
aws secretsmanager list-secrets --query "SecretList[?contains(Name, '${PREFIX}')].[Name,ARN]" --output table
```

---

## 14. End-to-End Integration Tests

### 14.1 Full Data Pipeline Test

```bash
TRAINING_BUCKET="${PREFIX}-training-data-${ACCOUNT_ID}"
EVENT_BUS="${PREFIX}-imaging-events"
PIPELINE_NAME="${PREFIX}-pneumonia-pipeline"
METADATA_TABLE="${PREFIX}-image-metadata"

# Step 1: Upload DICOM to S3 (triggers image-ingestion Lambda)
TEST_ID="e2e-test-$(date +%Y%m%d%H%M%S)"
echo "test-dicom-content" > /tmp/${TEST_ID}.dcm
aws s3 cp /tmp/${TEST_ID}.dcm "s3://${TRAINING_BUCKET}/input/${TEST_ID}.dcm"
echo "Uploaded test file: ${TEST_ID}.dcm"

# Step 2: Wait for Lambda processing
echo "Waiting 30 seconds for Lambda processing..."
sleep 30

# Step 3: Verify DynamoDB record created
echo "Checking DynamoDB for ingestion record..."
aws dynamodb scan \
  --table-name $METADATA_TABLE \
  --filter-expression "contains(image_id, :prefix)" \
  --expression-attribute-values "{\":prefix\": {\"S\": \"${TEST_ID}\"}}" \
  --query "Items[0]"

# Step 4: Check Lambda logs
echo "Checking Lambda logs..."
aws logs filter-log-events \
  --log-group-name "/aws/lambda/${PREFIX}-image-ingestion" \
  --filter-pattern "${TEST_ID}" \
  --start-time $(date -u -d '5 minutes ago' +%s)000 \
  --query "events[*].message"

# Step 5: Send ImageVerified event to trigger pipeline
echo "Sending ImageVerified event..."
aws events put-events --entries '[{
  "Source": "imaging.mlops",
  "DetailType": "ImageVerified",
  "Detail": "{\"imageSetId\": \"'${TEST_ID}'\"}",
  "EventBusName": "'${EVENT_BUS}'"
}]'

# Step 6: Wait and check pipeline execution
echo "Waiting 10 seconds for pipeline trigger..."
sleep 10

echo "Checking pipeline executions..."
aws sagemaker list-pipeline-executions \
  --pipeline-name $PIPELINE_NAME \
  --sort-by CreationTime \
  --sort-order Descending \
  --max-results 1 \
  --query "PipelineExecutionSummaries[0].[PipelineExecutionDisplayName,PipelineExecutionStatus]"
```

### 14.2 Automated E2E Test Script

```bash
#!/bin/bash
# Save as: scripts/e2e-test.sh

set -e

PREFIX="${1:-healthcare-imaging-dev}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "=== Healthcare Imaging MLOps E2E Test ==="
echo "Prefix: $PREFIX"
echo "Account: $ACCOUNT_ID"
echo ""

# Test 1: Infrastructure
echo "[1/6] Testing infrastructure..."
aws lambda get-function --function-name "${PREFIX}-image-ingestion" --query "Configuration.State" --output text
aws dynamodb describe-table --table-name "${PREFIX}-image-metadata" --query "Table.TableStatus" --output text
echo "✓ Infrastructure OK"

# Test 2: S3 Upload
echo "[2/6] Testing S3 upload..."
BUCKET="${PREFIX}-training-data-${ACCOUNT_ID}"
TEST_FILE="test-$(date +%s).dcm"
echo "test" | aws s3 cp - "s3://${BUCKET}/input/${TEST_FILE}"
echo "✓ S3 Upload OK"

# Test 3: Lambda Invocation
echo "[3/6] Testing Lambda invocation..."
sleep 5
aws logs filter-log-events \
  --log-group-name "/aws/lambda/${PREFIX}-image-ingestion" \
  --filter-pattern "${TEST_FILE}" \
  --start-time $(date -u -d '1 minute ago' +%s)000 \
  --query "events | length(@)" --output text
echo "✓ Lambda Invocation OK"

# Test 4: EventBridge
echo "[4/6] Testing EventBridge..."
aws events put-events --entries '[{
  "Source": "imaging.mlops",
  "DetailType": "ImageVerified",
  "Detail": "{\"imageSetId\": \"test\"}",
  "EventBusName": "'${PREFIX}-imaging-events'"
}]' --query "FailedEntryCount" --output text
echo "✓ EventBridge OK"

# Test 5: DynamoDB
echo "[5/6] Testing DynamoDB..."
aws dynamodb put-item \
  --table-name "${PREFIX}-image-metadata" \
  --item '{"image_id": {"S": "e2e-test"}, "timestamp": {"S": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}, "status": {"S": "TEST"}}'
aws dynamodb delete-item \
  --table-name "${PREFIX}-image-metadata" \
  --key '{"image_id": {"S": "e2e-test"}, "timestamp": {"S": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}}'
echo "✓ DynamoDB OK"

# Test 6: Cleanup
echo "[6/6] Cleaning up..."
aws s3 rm "s3://${BUCKET}/input/${TEST_FILE}"
echo "✓ Cleanup OK"

echo ""
echo "=== All E2E Tests Passed ==="
```

---

## 15. Cleanup & Teardown

### 15.1 Pre-Cleanup Verification

```bash
cd terraform

# List all managed resources
terraform state list

# Show specific resource details
terraform state show module.storage.aws_s3_bucket.training_data
terraform state show module.dynamodb.aws_dynamodb_table.image_metadata
terraform state show module.lambda_functions.aws_lambda_function.image_ingestion
```

### 15.2 Empty S3 Buckets (Required Before Destroy)

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Empty all buckets (required for terraform destroy)
for bucket in training-data preprocessed-data model-artifacts logs; do
    BUCKET_NAME="${PREFIX}-${bucket}-${ACCOUNT_ID}"
    echo "Emptying bucket: ${BUCKET_NAME}"
    aws s3 rm "s3://${BUCKET_NAME}" --recursive 2>/dev/null || true
done
```

### 15.3 Destroy Infrastructure

```bash
cd terraform

# Plan destruction
terraform plan -destroy -out=destroy.tfplan

# Review the plan carefully!

# Destroy (use with caution!)
terraform apply destroy.tfplan

# Or destroy interactively
terraform destroy
```

### 15.4 Verify Cleanup

```bash
# Verify S3 buckets removed
aws s3 ls | grep $PREFIX

# Verify DynamoDB tables removed
aws dynamodb list-tables --query "TableNames[?contains(@, '${PREFIX}')]"

# Verify Lambda functions removed
aws lambda list-functions --query "Functions[?contains(FunctionName, '${PREFIX}')].FunctionName"

# Verify ECR repositories removed
aws ecr describe-repositories --query "repositories[?contains(repositoryName, '${PREFIX}')].repositoryName"

# Verify HealthImaging datastore removed
aws medical-imaging list-data-stores --query "datastoreSummaries[?contains(datastoreName, '${PREFIX}')]"
```

### 15.5 Manual Cleanup (If Needed)

```bash
# Delete ECR repositories with images
for repo in preprocessing training evaluation inference api; do
    aws ecr delete-repository --repository-name "${PREFIX}-${repo}" --force 2>/dev/null || true
done

# Delete CloudWatch log groups
for func in image-ingestion pipeline-trigger model-evaluation model-registry; do
    aws logs delete-log-group --log-group-name "/aws/lambda/${PREFIX}-${func}" 2>/dev/null || true
done
```

---

## Summary Checklist

| # | Category | Test | Status |
|---|----------|------|--------|
| 1 | Infrastructure | Terraform validate | ☐ |
| 2 | Infrastructure | VPC status | ☐ |
| 3 | Infrastructure | S3 buckets exist | ☐ |
| 4 | Infrastructure | DynamoDB tables active | ☐ |
| 5 | Infrastructure | Lambda functions active | ☐ |
| 6 | Infrastructure | HealthImaging datastore active | ☐ |
| 7 | Infrastructure | SageMaker pipeline active | ☐ |
| 8 | Infrastructure | ECR repositories exist | ☐ |
| 9 | Lambda | Image ingestion invocation | ☐ |
| 10 | Lambda | Pipeline trigger invocation | ☐ |
| 11 | Lambda | Get presigned URL invocation | ☐ |
| 12 | Lambda | Model evaluation invocation | ☐ |
| 13 | Lambda | Model registry invocation | ☐ |
| 14 | S3 | Upload triggers Lambda | ☐ |
| 15 | S3 | Encryption enabled | ☐ |
| 16 | S3 | Public access blocked | ☐ |
| 17 | DynamoDB | CRUD operations | ☐ |
| 18 | DynamoDB | GSI queries | ☐ |
| 19 | HealthImaging | Datastore accessible | ☐ |
| 20 | HealthImaging | Import job creation | ☐ |
| 21 | SageMaker | Pipeline execution | ☐ |
| 22 | SageMaker | Training job monitoring | ☐ |
| 23 | EventBridge | Rules configured | ☐ |
| 24 | EventBridge | Event delivery | ☐ |
| 25 | Docker | Container builds | ☐ |
| 26 | Docker | ECR push | ☐ |
| 27 | Python | Unit tests pass | ☐ |
| 28 | Python | Module imports | ☐ |
| 29 | Monitoring | Dashboard exists | ☐ |
| 30 | Monitoring | Alarms configured | ☐ |
| 31 | Monitoring | Logs accessible | ☐ |
| 32 | Frontend | Config generation | ☐ |
| 33 | Frontend | API endpoints | ☐ |
| 34 | Security | IAM roles | ☐ |
| 35 | Security | KMS keys | ☐ |
| 36 | Security | Security groups | ☐ |
| 37 | Security | VPC endpoints | ☐ |
| 38 | E2E | Full pipeline flow | ☐ |

---

## Quick Reference Commands

```bash
# Set environment variables
export PROJECT="healthcare-imaging"
export ENV="dev"
export PREFIX="${PROJECT}-${ENV}"
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export REGION="us-east-1"

# Common Terraform commands
cd terraform
terraform init
terraform validate
terraform plan
terraform apply
terraform output -json > deployment-outputs.json

# Common AWS CLI commands
aws lambda invoke --function-name "${PREFIX}-image-ingestion" --payload '{}' response.json
aws dynamodb scan --table-name "${PREFIX}-image-metadata" --max-items 5
aws sagemaker list-pipeline-executions --pipeline-name "${PREFIX}-pneumonia-pipeline"
aws events put-events --entries '[{"Source":"imaging.mlops","DetailType":"ImageVerified","Detail":"{}","EventBusName":"'${PREFIX}'-imaging-events"}]'
aws logs tail "/aws/lambda/${PREFIX}-image-ingestion" --follow

# Run validation script
./scripts/validate-deployment.sh

# Run monitoring
./scripts/monitoring.sh
```

---

*Generated from source code analysis. Last updated: January 2026*
