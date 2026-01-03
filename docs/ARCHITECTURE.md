# System Architecture
## Healthcare Imaging MLOps Platform - Complete System Architecture

---

## 1. SYSTEM OVERVIEW

### Value Proposition
- **Zero-Latency Streaming**: Stream 1GB+ Chest CT scans to mobile browsers at 60fps
- **Automated MLOps**: Continuous model improvement without manual data scientist intervention
- **40% Cost Savings**: HTJ2K compression reduces storage costs vs. standard S3
- **HIPAA Compliant**: End-to-end encryption, audit logging, data residency controls

### Architecture Type
**Event-Driven Serverless with Batch ML Processing**

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         DISTRIBUTED RADIOLOGISTS                        │
│                          (Mobile Browsers)                               │
└───────────────────────────┬──────────────────────────────────────────────┘
                            │
                    ┌───────▼────────┐
                    │  API Gateway   │
                    │  (CORS, Auth)  │
                    └───────┬────────┘
                            │
        ┌───────────────────┼───────────────────┐
        │                   │                   │
┌───────▼────────┐  ┌──────▼──────┐  ┌────────▼────────┐
│ HealthImaging  │  │  S3 Ingress │  │  DynamoDB State │
│  (Streaming)   │  │   Bucket    │  │   & Metadata    │
└────────────────┘  └──────┬──────┘  └────────────────┘
                           │
                  ┌────────▼────────┐
                  │   EventBridge   │
                  │  (Orchestration)│
                  └────────┬────────┘
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
┌───────▼──────┐  ┌───────▼────────┐  ┌─────▼──────┐
│   Lambda      │  │  SageMaker     │  │ CloudWatch │
│   Triggers    │  │  Pipelines     │  │ Monitoring │
└───────┬──────┘  └───────┬────────┘  └────────────┘
        │                 │
        └────────┬────────┘
                 │
    ┌────────────▼───────────────┐
    │  SageMaker Processing Job  │
    │  (Preprocessing)           │
    └────────────┬───────────────┘
                 │
    ┌────────────▼───────────────┐
    │  SageMaker Training Job     │
    │  (GPU-Accelerated)         │
    └────────────┬───────────────┘
                 │
    ┌────────────▼───────────────┐
    │  Model Evaluation          │
    │  (Automated Approval)      │
    └────────────┬───────────────┘
                 │
    ┌────────────▼───────────────┐
    │  Model Registry &          │
    │  Endpoint Deployment       │
    └────────────────────────────┘
```

---

## 2. DETAILED COMPONENT ARCHITECTURE

### 2.1 AWS HealthImaging Layer
**Purpose**: Zero-latency DICOM image streaming to mobile browsers

```
┌────────────────────────────────────────────────────┐
│        AWS HealthImaging Data Store                │
├────────────────────────────────────────────────────┤
│ • Native DICOM storage & indexing                 │
│ • HTJ2K lossless compression (40% savings)        │
│ • Multi-frame CT/MRI support                      │
│ • Sub-second retrieval (60fps streaming)          │
│ • S3 integration for ingestion                    │
│ • KMS encryption at rest                         │
│ • VPC endpoint for private access                │
│                                                   │
│ Streaming Path:                                  │
│ 1. Doctor opens app on tablet (4G)               │
│ 2. Mobile browser requests image streaming URL   │
│ 3. Lambda generates pre-signed URL               │
│ 4. HealthImaging streams HTJ2K-compressed data   │
│ 5. Browser decompresses in real-time             │
│ 6. Display at 60fps with zero buffering          │
│                                                   │
│ Cost Impact:                                     │
│ • Standard S3: $0.023/GB                         │
│ • HealthImaging: $0.0023/GB (100x cheaper)      │
│ • HTJ2K compression: 40% additional savings     │
└────────────────────────────────────────────────────┘
```

**Key Resources**:
- `healthimaging.py` client library
- Pre-signed URL generator
- Streaming protocol handlers
- S3 DICOM ingestion buckets

---

### 2.2 Data Ingestion Pipeline
**Purpose**: Automated DICOM upload, validation, and verification

```
┌─────────────────────────────────────────────────────────┐
│              DICOM File Upload (1GB+)                   │
│         (PACS, Hospital Integration, Manual)           │
└────────────────┬────────────────────────────────────────┘
                 │
         ┌───────▼────────┐
         │  S3 Bucket     │
         │  (Upload/Inbox)│
         └───────┬────────┘
                 │ (S3:ObjectCreated event)
         ┌───────▼────────────────┐
         │  EventBridge Rule      │
         │  (DICOMUploaded)       │
         └───────┬────────────────┘
                 │
         ┌───────▼──────────────┐
         │ Lambda Function      │
         │ (ImageIngestion)     │
         ├──────────────────────┤
         │ • Validate DICOM     │
         │ • Extract metadata   │
         │ • Normalize orientation
         │ • Generate checksum  │
         │ • Log audit trail    │
         └───────┬──────────────┘
                 │
         ┌───────▼──────────────────────┐
         │ HealthImaging Data Store     │
         │ (Permanent DICOM Repository) │
         ├──────────────────────────────┤
         │ • Auto-indexed               │
         │ • HTJ2K-compressed          │
         │ • Patient level access control
         │ • Immutable archive copy     │
         └───────┬──────────────────────┘
                 │
         ┌───────▼──────────────┐
         │ DynamoDB             │
         │ (Image Tracking)     │
         ├──────────────────────┤
         │ • Ingestion status   │
         │ • Verification state │
         │ • Radiologist notes  │
         └──────────────────────┘
```

---

### 2.3 SageMaker Training Pipeline (CI/CD for Models)
**Purpose**: Automated, triggered model retraining with new verified data

```
┌────────────────────────────────────────────────────────┐
│     Radiologist Verifies Image in HealthImaging       │
│         (Manual approval: high-confidence)             │
└─────────────────┬──────────────────────────────────────┘
                  │ (ImageVerified event)
          ┌───────▼────────────────┐
          │   EventBridge Rule     │
          │ (ImageVerified Filter) │
          └───────┬────────────────┘
                  │
          ┌───────▼───────────────────┐
          │ Lambda: PipelineTrigger   │
          │                           │
          │ • Collect verified images │
          │ • Verify data quality     │
          │ • Prepare training batch  │
          └───────┬───────────────────┘
                  │
          ┌───────▼──────────────────────────┐
          │ SageMaker Pipeline Execution     │
          │ (Automated training workflow)    │
          ├───────────────────────────────────┤
          │                                   │
          │ STEP 1: Preprocessing             │
          │ ┌────────────────────────────┐   │
          │ │ • Normalize pixel values   │   │
          │ │ • Data augmentation        │   │
          │ │ • Quality validation       │   │
          │ │ • Create train/test split  │   │
          │ └────────────────────────────┘   │
          │           │                      │
          │ STEP 2: Training                 │
          │ ┌────────┴──────────────────┐   │
          │ │ • ResNet-50 architecture  │   │
          │ │ • GPU distributed training│   │
          │ │ • 50 epochs, early stop   │   │
          │ │ • Checkpoint management   │   │
          │ └────────────────────────────┘   │
          │           │                      │
          │ STEP 3: Evaluation               │
          │ ┌────────┴──────────────────┐   │
          │ │ • Accuracy on test set    │   │
          │ │ • Precision/Recall/F1    │   │
          │ │ • ROC-AUC curves         │   │
          │ │ • Generate metrics JSON   │   │
          │ └────────────────────────────┘   │
          │           │                      │
          │ STEP 4: Approval Condition       │
          │ ┌────────┴──────────────────┐   │
          │ │ IF accuracy > 85%:        │   │
          │ │   Register model          │   │
          │ │ ELSE:                     │   │
          │ │   Log failure, notify     │   │
          │ └────────────────────────────┘   │
          │                                   │
          └───────┬──────────────────────────┘
                  │
    ┌─────────────┴─────────────┐
    │                           │
┌───▼────────────────┐   ┌─────▼──────────────┐
│ Model Registry     │   │ CloudWatch Metrics │
│ (Versioning)       │   │ (Performance Data) │
├────────────────────┤   ├────────────────────┤
│ • Version N model  │   │ • Training time    │
│ • Previous versions│   │ • Accuracy trend   │
│ • Metadata         │   │ • Data quality     │
│ • Approval status  │   │ • Cost tracking    │
└────────────────────┘   └────────────────────┘
```

**Pipeline Code**: `python/src/pipeline/pipeline_builder.py`

---

### 2.4 EventBridge Orchestration
**Purpose**: Coordinating events and triggering automated actions

```
┌─────────────────────────────────────────────────────────────┐
│              EventBridge Custom Event Bus                   │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  RULE 1: ImageVerified → Trigger SageMaker Pipeline         │
│  ├─ Source: aws.healthimaging                              │
│  ├─ Event: HealthImaging ImageVerified                     │
│  └─ Target: SageMaker Pipeline (PipelineExecutionArn)      │
│                                                              │
│  RULE 2: TrainingComplete → Run Evaluation Lambda          │
│  ├─ Source: aws.sagemaker                                  │
│  ├─ Event: SageMaker Training Job State Change             │
│  ├─ Condition: status == "Completed"                       │
│  └─ Target: Lambda (ModelEvaluation)                       │
│                                                              │
│  RULE 3: EvaluationPassed → Register Model                 │
│  ├─ Source: imaging.mlops (custom)                         │
│  ├─ Event: ModelEvaluationPassed                           │
│  ├─ Condition: accuracy >= threshold                       │
│  └─ Target: Lambda (ModelRegistry)                         │
│                                                              │
│  RULE 4: MetricViolation → Send Alert                      │
│  ├─ Source: aws.cloudwatch                                 │
│  ├─ Event: CloudWatch Alarm State Change                   │
│  └─ Target: SNS Topic (Alert Notification)                 │
│                                                              │
│  RULE 5: PipelineFailure → Notify Team                     │
│  ├─ Source: aws.sagemaker                                  │
│  ├─ Event: Training Job Failed                             │
│  └─ Target: SNS + Lambda (ErrorLogging)                    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

**Event Flow**:
```
Image Verified (Manual)
    ↓ (30s delay)
Trigger Training Pipeline
    ↓ (5-30 min depending on data)
Training Complete
    ↓ (10 min)
Evaluation Complete
    ↓ (Conditional)
Model Registered & Ready
    ↓ (Optional: Deploy Endpoint)
Live Inference Available
```

---

### 2.5 Lambda Functions (Serverless Event Handlers)

```
┌──────────────────────────────────────────────────────────────┐
│            LAMBDA FUNCTION 1: Image Ingestion              │
├──────────────────────────────────────────────────────────────┤
│ Trigger: S3 ObjectCreated (DICOM upload)                   │
│ Timeout: 300s                                              │
│ Memory: 512 MB                                             │
│                                                             │
│ Responsibilities:                                          │
│ • Validate DICOM format (pydicom library)                 │
│ • Extract patient/study metadata                          │
│ • Move to HealthImaging ingestion folder                  │
│ • Update DynamoDB tracking table                          │
│ • Publish "ImageIngested" event                           │
│ • Log audit trail for compliance                          │
│                                                             │
│ Environment Variables:                                     │
│ • HEALTHIMAGING_DATASTORE_ID                             │
│ • DYNAMODB_TRACKING_TABLE                                │
│ • S3_INGESTION_BUCKET                                    │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│         LAMBDA FUNCTION 2: Pipeline Trigger               │
├──────────────────────────────────────────────────────────────┤
│ Trigger: EventBridge (ImageVerified)                      │
│ Timeout: 60s                                              │
│ Memory: 256 MB                                            │
│                                                             │
│ Responsibilities:                                          │
│ • Receive ImageVerified event from EventBridge            │
│ • Collect all verified images since last training        │
│ • Prepare SageMaker pipeline parameters                   │
│ • Start pipeline execution                                │
│ • Publish "PipelineTriggered" event                       │
│ • Send confirmation notification                          │
│                                                             │
│ Environment Variables:                                     │
│ • SAGEMAKER_PIPELINE_NAME                               │
│ • SAGEMAKER_PIPELINE_ARN                                │
│ • TRAINING_DATA_BUCKET                                  │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│         LAMBDA FUNCTION 3: Model Evaluation               │
├──────────────────────────────────────────────────────────────┤
│ Trigger: EventBridge (SageMaker Training Complete)        │
│ Timeout: 900s                                             │
│ Memory: 1024 MB                                           │
│                                                             │
│ Responsibilities:                                          │
│ • Download model artifacts from S3                        │
│ • Load test dataset from S3                              │
│ • Run inference on test set                              │
│ • Calculate accuracy, precision, recall, F1-score        │
│ • Generate evaluation report (JSON)                       │
│ • Store metrics in DynamoDB                              │
│ • Publish CloudWatch metrics                             │
│ • Decide approval/rejection                              │
│ • Emit evaluation event to EventBridge                   │
│                                                             │
│ Environment Variables:                                     │
│ • MODEL_ARTIFACTS_BUCKET                                │
│ • TEST_DATA_BUCKET                                      │
│ • DYNAMODB_METRICS_TABLE                               │
│ • ACCURACY_THRESHOLD                                    │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│         LAMBDA FUNCTION 4: Model Registry                 │
├──────────────────────────────────────────────────────────────┤
│ Trigger: EventBridge (ModelEvaluationPassed)              │
│ Timeout: 300s                                             │
│ Memory: 512 MB                                            │
│                                                             │
│ Responsibilities:                                          │
│ • Register model in SageMaker Model Registry              │
│ • Create model package version                           │
│ • Set approval status to "Approved"                      │
│ • Tag with metadata (training date, data version, etc)  │
│ • Optionally deploy to inference endpoint                │
│ • Update DynamoDB with deployment status                 │
│ • Send deployment notification                           │
│                                                             │
│ Environment Variables:                                     │
│ • SAGEMAKER_ROLE_ARN                                    │
│ • MODEL_PACKAGE_GROUP_NAME                             │
│ • INFERENCE_ENDPOINT_NAME (optional)                   │
│ • MODEL_ARTIFACTS_BUCKET                               │
└──────────────────────────────────────────────────────────────┘
```

---

### 2.6 Storage Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   S3 BUCKET STRUCTURE                       │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Bucket 1: training-data-{account}                         │
│  ├── upload/                    # Temporary DICOM files   │
│  │   └── {timestamp}/{dicom}                              │
│  │                                                         │
│  ├── validated/                 # After validation        │
│  │   └── {image-set-id}/{frame}.dcm                      │
│  │                                                         │
│  ├── verified/                  # After radiologist OK   │
│  │   └── {image-set-id}/{frame}.dcm                      │
│  │                                                         │
│  └── quarantine/                # Failed validation      │
│      └── {image-set-id}/                                 │
│          └── {reason}.txt                                │
│                                                            │
│  Bucket 2: preprocessed-data-{account}                    │
│  ├── train/                     # Training dataset       │
│  │   ├── images/                                         │
│  │   ├── labels/                                         │
│  │   └── manifest.json                                  │
│  │                                                       │
│  └── test/                      # Evaluation dataset    │
│      ├── images/                                         │
│      ├── labels/                                         │
│      └── manifest.json                                  │
│                                                            │
│  Bucket 3: model-artifacts-{account}                      │
│  ├── models/                    # Trained models        │
│  │   ├── v1/                                            │
│  │   │   ├── model.tar.gz                              │
│  │   │   ├── metadata.json                             │
│  │   │   └── evaluation_metrics.json                   │
│  │   ├── v2/                                           │
│  │   └── ...                                           │
│  │                                                      │
│  └── checkpoints/               # Training checkpoints │
│      └── {training-job}/                               │
│          └── {epoch}.pt                               │
│                                                            │
│  Bucket 4: logs-{account}                                  │
│  ├── cloudtrail/                # Audit logs            │
│  ├── cloudwatch/                # Log streams           │
│  ├── sagemaker/                 # Training logs         │
│  └── healthimaging/             # API call logs         │
│                                                            │
└─────────────────────────────────────────────────────────────┘

Security Configuration:
✓ Versioning: Enabled (all buckets)
✓ Encryption: KMS keys (customer-managed)
✓ Access: VPC endpoint only (private)
✓ Logging: CloudTrail + CloudWatch
✓ Lifecycle: 90d → Intelligent-Tiering, 180d → Glacier
```

---

### 2.7 Networking & VPC Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                  AWS REGION: us-east-1                       │
├──────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌────────────────────────────────────────────────────────┐ │
│  │              VPC: 10.0.0.0/16                          │ │
│  │                                                        │ │
│  │  ┌──────────────────────────────────────────────────┐ │ │
│  │  │    Public Subnets (2 AZs) - NAT Only             │ │ │
│  │  │    10.0.1.0/24 (us-east-1a)                     │ │ │
│  │  │    10.0.2.0/24 (us-east-1b)                     │ │ │
│  │  └──────────────────────────────────────────────────┘ │ │
│  │           │                                            │ │
│  │           ↓ (VPC Endpoints)                            │ │
│  │  ┌──────────────────────────────────────────────────┐ │ │
│  │  │ AWS Managed Services (Private)                  │ │ │
│  │  │ • S3 Gateway Endpoint                           │ │ │
│  │  │ • DynamoDB Gateway Endpoint                     │ │ │
│  │  │ • SageMaker Interface Endpoint                  │ │ │
│  │  │ • HealthImaging Interface Endpoint             │ │ │
│  │  │ • EventBridge Interface Endpoint               │ │ │
│  │  │ • KMS Interface Endpoint                       │ │ │
│  │  │ • SecretsManager Interface Endpoint            │ │ │
│  │  └──────────────────────────────────────────────────┘ │ │
│  │           ↑                                            │ │
│  │  ┌──────────┴──────────────────────────────────────┐ │ │
│  │  │    Private Subnets (2 AZs)                      │ │ │
│  │  │    10.0.10.0/24 (us-east-1a)                   │ │ │
│  │  │    10.0.20.0/24 (us-east-1b)                   │ │ │
│  │  │                                                 │ │ │
│  │  │  SageMaker Compute:                            │ │ │
│  │  │  • Training Instances (GPU)                    │ │ │
│  │  │  • Processing Instances                        │ │ │
│  │  │  • Notebook Instances                          │ │ │
│  │  │                                                 │ │ │
│  │  │  Lambda Functions:                             │ │ │
│  │  │  • Image Ingestion                             │ │ │
│  │  │  • Pipeline Trigger                            │ │ │
│  │  │  • Model Evaluation                            │ │ │
│  │  │  • Model Registry                              │ │ │
│  │  │                                                 │ │ │
│  │  │  Security Group: sg-mlops-private              │ │ │
│  │  │  • Ingress: 443 (HTTPS to VPC endpoints)      │ │ │
│  │  │  • Egress: 443 (to service endpoints)          │ │ │
│  │  └──────────────────────────────────────────────────┘ │ │
│  │                                                        │ │
│  │  NAT Gateway (High Availability):                     │ │
│  │  • us-east-1a: Elastic IP                            │ │
│  │  • us-east-1b: Elastic IP                            │ │
│  │                                                        │ │
│  └────────────────────────────────────────────────────────┘ │
│                                                               │
└──────────────────────────────────────────────────────────────┘

Network Benefits:
✓ No internet exposure (fully private)
✓ VPC endpoints avoid NAT/IGW costs
✓ HighAvailability across 2 AZs
✓ Encrypted transit (TLS 1.2+)
✓ Flow logs for security analysis
```

---

### 2.8 Monitoring & Observability

```
┌─────────────────────────────────────────────────────────────┐
│              CloudWatch Dashboards                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│ Dashboard 1: HealthImaging Metrics                         │
│ ├─ Image Retrieval Latency (avg, p99)                     │
│ ├─ Bytes Retrieved (per-image, trend)                     │
│ ├─ API Call Count (per-operation)                         │
│ ├─ Data Store Size (GB)                                  │
│ ├─ Connection Count (concurrent streams)                 │
│ └─ HTJ2K Compression Ratio (%)                           │
│                                                              │
│ Dashboard 2: SageMaker Pipeline                           │
│ ├─ Pipeline Execution Count (per day)                    │
│ ├─ Successful vs. Failed Executions                      │
│ ├─ Average Execution Time (minutes)                      │
│ ├─ Training Job Duration (per epoch)                     │
│ ├─ Data Pre-processing Time                              │
│ ├─ Model Accuracy Trend (over time)                      │
│ ├─ Precision/Recall/F1-Score (per model)                │
│ └─ CPU/GPU Utilization (%)                              │
│                                                              │
│ Dashboard 3: MLOps Custom Metrics                         │
│ ├─ Data Quality Score (validation pass %)               │
│ ├─ Model Approval Rate (approved/total)                 │
│ ├─ Average Time to Model Deployment                     │
│ ├─ Model Drift Score (data vs. baseline)                │
│ ├─ Cost per Model Training ($)                          │
│ ├─ Training Data Volume (GB ingested)                   │
│ └─ Inference Endpoint Invocations (per model)          │
│                                                              │
└─────────────────────────────────────────────────────────────┘

Alarms:
┌────────────────────────────────────────────────────────────┐
│ CRITICAL ALERTS                                           │
├────────────────────────────────────────────────────────────┤
│ • HealthImaging Retrieval Latency > 1000ms    → ALARM   │
│ • SageMaker Training Failure (status=Failed)  → ALARM   │
│ • Model Accuracy < 85%                        → ALARM   │
│ • Data Store Connection Errors > 5/min        → ALARM   │
│ • Lambda Function Errors > 1%                 → ALARM   │
│ • DynamoDB Throttling Events                  → ALARM   │
│ • S3 Storage Exceeded Budget                  → ALARM   │
│ • Audit Log Lag > 15 minutes                  → ALARM   │
│                                                           │
│ Action: SNS Topic → Slack/Email/PagerDuty               │
└────────────────────────────────────────────────────────────┘

Logging:
┌────────────────────────────────────────────────────────────┐
│ CloudWatch Log Groups (7-day retention)                   │
├────────────────────────────────────────────────────────────┤
│ /aws/healthimaging/{project}/{env}                        │
│ /aws/sagemaker/training-jobs/{job-id}                    │
│ /aws/lambda/image-ingestion                              │
│ /aws/lambda/pipeline-trigger                             │
│ /aws/lambda/model-evaluation                             │
│ /aws/lambda/model-registry                               │
│ /aws/events/{event-bus-name}                             │
│ /aws/kms/{key-id}                                        │
│ /aws/iam/                                                │
│                                                           │
│ Format: JSON with timestamps, trace IDs, request/response │
│ Encryption: KMS-encrypted                                │
│ Retention: Prod=30d, Dev=7d                             │
└────────────────────────────────────────────────────────────┘
```

---

## 3. DATA FLOW (End-to-End)

### Scenario: Radiologist Uploads & Verifies Chest CT Scan

**Timeline**: 0-45 minutes

```
T+0:00  Radiologist
        └─ Uploads 1GB Chest CT DICOM file to S3 ingestion bucket
           via web portal or integration API
           
T+0:05  S3 Event
        └─ S3 ObjectCreated event triggered
           
T+0:10  Lambda: ImageIngestion
        ├─ Validates DICOM format
        ├─ Extracts metadata (PatientID, StudyDate, etc.)
        ├─ Moves to HealthImaging ingestion folder
        ├─ Updates DynamoDB tracking: status = "INGESTED"
        └─ Publishes CloudWatch metric
        
T+0:15  HealthImaging DataStore
        ├─ Indexes DICOM file
        ├─ Applies HTJ2K compression (original 1GB → ~600MB)
        ├─ Makes available via secure streaming endpoint
        └─ Updates data store inventory
        
T+0:20  Radiologist's Browser
        ├─ Requests image streaming URL from API Gateway
        ├─ Lambda generates pre-signed streaming URL
        ├─ Browser opens WebSocket to HealthImaging endpoint
        ├─ Streams HTJ2K-compressed frames over 4G
        ├─ Decompresses and displays at 60fps
        └─ Zero buffering, instant viewport panning
        
T+5:00  Radiologist Reviews
        └─ Examines 512 CT slices
           Findings: Pneumonia suspected in right lower lobe
           
T+10:00 Radiologist Verification
        ├─ Clicks "VERIFY AS GROUND TRUTH" button in UI
        ├─ System posts to EventBridge:
        │  {
        │    "source": "aws.healthimaging",
        │    "detail-type": "HealthImaging ImageVerified",
        │    "detail": {
        │      "imageSetId": "img-12345",
        │      "dataStoreId": "store-67890",
        │      "verifiedBy": "radiologist@hospital.com",
        │      "verificationTime": "2024-01-03T...",
        │      "findings": "Pneumonia RLL"
        │    }
        │  }
        └─ Updates DynamoDB: status = "VERIFIED", verified_at = T+10:00
        
T+10:30 EventBridge Rule Fires
        └─ Matches: source=aws.healthimaging, detail-type=ImageVerified
           Target: Lambda (PipelineTrigger)
        
T+10:45 Lambda: PipelineTrigger
        ├─ Collects all verified images since last training (batch of N images)
        ├─ Creates SageMaker pipeline input:
        │  {
        │    "TrainingDataPath": "s3://training-data/verified/batch-001/",
        │    "TestDataPath": "s3://training-data/test-split/",
        │    "AccuracyThreshold": 0.85,
        │    "TrainingInstanceType": "ml.p3.2xlarge"
        │  }
        ├─ Calls StartPipelineExecution()
        └─ Updates DynamoDB: pipeline_status = "QUEUED"
        
T+11:00 SageMaker Pipeline Starts
        └─ Execution ID: execution-20240103-110000
        
T+11:10 Step 1: Data Preprocessing
        ├─ SageMaker Processing Job (ml.m5.2xlarge, 1 instance)
        ├─ Normalizes pixel values (HU units → 0-1)
        ├─ Applies data augmentation (rotations, flips, noise)
        ├─ Splits into train (80%) / test (20%)
        ├─ Generates manifest files with labels
        ├─ Saves to S3: s3://preprocessed-data/batch-001/
        └─ Logs: ✓ CloudWatch /aws/sagemaker/preprocessing
        
T+15:00 Step 2: Model Training
        ├─ SageMaker Training Job (ml.p3.2xlarge GPU, 1 instance)
        ├─ Model: ResNet-50 pre-trained on ImageNet
        ├─ Inputs: Preprocessed training data
        ├─ Config:
        │  - Epochs: 50
        │  - Batch size: 32
        │  - Learning rate: 0.001
        │  - Loss: Binary cross-entropy (pneumonia: yes/no)
        │  - Optimizer: Adam
        │  - Early stopping: patience=5, metric=val_loss
        ├─ Saves checkpoints every epoch
        ├─ Tracks metrics: loss, accuracy, precision, recall
        └─ Logs: ✓ CloudWatch /aws/sagemaker/training-jobs
        
T+40:00 Training Complete (25 minutes of GPU compute)
        ├─ Model artifact saved: s3://model-artifacts/v42/model.tar.gz
        ├─ Metrics saved: s3://model-artifacts/v42/metrics.json
        │  {
        │    "final_accuracy": 0.9125,
        │    "final_precision": 0.88,
        │    "final_recall": 0.94,
        │    "final_f1": 0.91,
        │    "training_time_seconds": 1500
        │  }
        └─ Publishes SageMaker event:
           "SageMaker Training Job State Change" → COMPLETED
        
T+40:15 EventBridge Rule Fires
        └─ Target: Lambda (ModelEvaluation)
        
T+40:30 Lambda: ModelEvaluation
        ├─ Downloads model.tar.gz from S3
        ├─ Extracts and loads model (PyTorch)
        ├─ Loads test dataset from S3
        ├─ Runs inference on 1000 test images
        ├─ Generates prediction scores
        ├─ Compares to ground truth labels
        ├─ Calculates metrics:
        │  - Accuracy: 91.25%
        │  - Precision: 88%
        │  - Recall: 94%
        │  - F1-Score: 91%
        │  - ROC-AUC: 0.96
        ├─ Saves evaluation report: s3://evaluation-reports/v42.json
        ├─ Stores in DynamoDB:
        │  PK: model_version="v42"
        │  SK: evaluation_timestamp="2024-01-03T40:30"
        │  Data: {accuracy: 0.9125, precision: 0.88, ...}
        ├─ Checks condition: accuracy (0.9125) >= threshold (0.85)
        ├─ Result: ✓ PASSED
        └─ Publishes event to EventBridge:
           {
             "source": "imaging.mlops",
             "detail-type": "ModelEvaluationPassed",
             "detail": {
               "model_version": "v42",
               "accuracy": 0.9125,
               "recommendation": "APPROVE"
             }
           }
        
T+41:00 EventBridge Rule Fires
        └─ Target: Lambda (ModelRegistry)
        
T+41:15 Lambda: ModelRegistry
        ├─ Calls SageMaker CreateModelPackage()
        ├─ Registers model in Model Registry
        │  - Package name: pneumonia-detector-v42
        │  - Status: PendingApproval → Approved
        │  - Metadata:
        │    {
        │      "accuracy": 0.9125,
        │      "training_data_date": "2024-01-03",
        │      "training_instances": 1,
        │      "training_duration_minutes": 25,
        │      "inference_framework": "PyTorch",
        │      "compatible_endpoints": [
        │        "pneumonia-detector-realtime",
        │        "pneumonia-detector-batch"
        │      ]
        │    }
        ├─ Updates DynamoDB: model_status = "REGISTERED"
        ├─ Optionally deploys to SageMaker endpoint (if enabled)
        └─ Sends notification:
           {
             "event": "ModelApproved",
             "model_version": "v42",
             "accuracy": "91.25%",
             "action": "Ready for deployment"
           }
        
T+45:00 COMPLETE
        └─ New pneumonia detection model ready in registry
           Can be deployed to production inference endpoint
           or used in batch processing for diagnostic support
```

---

## 4. SECURITY ARCHITECTURE

### 4.1 Encryption

```
┌────────────────────────────────────────────────────────────┐
│ ENCRYPTION STRATEGY                                       │
├────────────────────────────────────────────────────────────┤
│                                                             │
│ At Rest:                                                  │
│ ├─ S3 Buckets: KMS Customer-Managed Keys                 │
│ │  └─ Separate keys per bucket (training, models, logs)  │
│ ├─ DynamoDB Tables: KMS Customer-Managed Keys            │
│ ├─ HealthImaging DataStore: KMS Customer-Managed Keys   │
│ ├─ EBS Volumes (Training instances): KMS keys           │
│ ├─ CloudWatch Logs: KMS keys                            │
│ └─ Secrets Manager: KMS keys                            │
│                                                             │
│ In Transit:                                              │
│ ├─ All API calls: TLS 1.2+ (enforced via policy)        │
│ ├─ VPC to endpoints: PrivateLink (encrypted)            │
│ ├─ Cross-region (future): TLS 1.3                       │
│ └─ Mobile browser to API: HTTPS with cert pinning       │
│                                                             │
│ Key Management:                                          │
│ ├─ KMS Key Policy: Only HIPAA-compliant roles           │
│ ├─ Key Rotation: Annual (AWS-managed)                   │
│ ├─ Key Access Audit: CloudTrail logs all key usage      │
│ ├─ Root account: Disabled key usage (via policy)        │
│ └─ Cross-account: Not permitted (single account only)   │
│                                                             │
└────────────────────────────────────────────────────────────┘
```

### 4.2 Identity & Access Control

```
┌────────────────────────────────────────────────────────────┐
│ IAM ROLES & POLICIES                                      │
├────────────────────────────────────────────────────────────┤
│                                                             │
│ SageMaker Execution Role:                                │
│ ├─ Permissions: Read training data, write artifacts      │
│ ├─ Trust relationship: SageMaker service                 │
│ ├─ Inline policy: Minimal (least privilege)            │
│ └─ Resource restrictions:                               │
│    └─ S3: arn:aws:s3:::training-data/*, models/*      │
│         (NOT upload/*, quarantine/*, logs/*)            │
│                                                             │
│ Lambda Execution Roles (per function):                  │
│ ├─ ImageIngestion:                                      │
│ │  ├─ s3:GetObject, s3:PutObject (ingestion bucket)    │
│ │  ├─ dynamodb:PutItem, dynamodb:UpdateItem            │
│ │  ├─ healthimaging:CreateImageSet                     │
│ │  └─ cloudwatch:PutMetricData                         │
│ │                                                       │
│ ├─ PipelineTrigger:                                     │
│ │  ├─ sagemaker:StartPipelineExecution                │
│ │  ├─ dynamodb:GetItem, UpdateItem                     │
│ │  ├─ s3:ListBucket, GetObject                         │
│ │  └─ cloudwatch:PutMetricData                         │
│ │                                                       │
│ ├─ ModelEvaluation:                                     │
│ │  ├─ s3:GetObject (models, test data)                 │
│ │  ├─ s3:PutObject (evaluation reports)                │
│ │  ├─ dynamodb:PutItem (metrics)                       │
│ │  ├─ sagemaker:CreateModel, CreateEndpointConfig      │
│ │  └─ cloudwatch:PutMetricData                         │
│ │                                                       │
│ └─ ModelRegistry:                                        │
│    ├─ sagemaker:CreateModelPackage, UpdateModelPackage │
│    ├─ dynamodb:UpdateItem                              │
│    ├─ sagemaker:CreateEndpoint (if deploying)          │
│    └─ sns:Publish (notifications)                       │
│                                                             │
│ EventBridge Service Role:                               │
│ ├─ sagemaker:StartPipelineExecution                    │
│ ├─ lambda:InvokeFunction (all MLOps lambdas)          │
│ ├─ sns:Publish (alert topic)                           │
│ └─ dynamodb:PutItem (event logging)                     │
│                                                             │
│ Radiologist API User (Cognito):                         │
│ ├─ healthimaging:GetImageSet, GetImageSetMetadata      │
│ ├─ healthimaging:SearchImageSets (own patient data)   │
│ ├─ No write permissions (read-only)                    │
│ └─ Scope: PatientIDs assigned by organization          │
│                                                             │
└────────────────────────────────────────────────────────────┘
```

### 4.3 Compliance (HIPAA)

```
┌────────────────────────────────────────────────────────────┐
│ HIPAA COMPLIANCE CONTROLS                                │
├────────────────────────────────────────────────────────────┤
│                                                             │
│ Data Encryption:     ✓ AES-256 at rest, TLS 1.2+ in transit
│ Access Control:      ✓ MFA + IAM + Cognito              │
│ Audit Logging:       ✓ CloudTrail (all API calls)       │
│ Integrity Checking:  ✓ S3 object tags, ETag validation  │
│ Deidentification:    ✓ DICOM PHI field stripping        │
│ Data Retention:      ✓ Configurable lifecycle policies  │
│ Backup & Recovery:   ✓ S3 versioning, cross-region     │
│ Incident Response:   ✓ AWS GuardDuty + Manual procedures
│ Workforce Auth:      ✓ Single sign-on (AWS SSO)        │
│ Minimum Necessary:   ✓ Query-based access (by PatientID)
│                                                             │
│ Audit Trail (7-year retention):                         │
│ ├─ CloudTrail: All AWS API calls                        │
│ ├─ S3 access logs: Object-level operations              │
│ ├─ VPC Flow Logs: Network traffic analysis              │
│ ├─ CloudWatch Logs: Application events                  │
│ ├─ KMS Logs: Key usage (encrypt/decrypt)               │
│ ├─ Lambda logs: Function invocations                    │
│ └─ DynamoDB Logs: Table operations                      │
│                                                             │
│ Breach Notification Procedures:                         │
│ ├─ Detection: CloudWatch Alarms + GuardDuty             │
│ ├─ Containment: Automatic resource isolation            │
│ ├─ Investigation: Logs exported to secure audit bucket  │
│ ├─ Notification: SNS to compliance team within 24hrs    │
│ └─ Documentation: Incident report generation            │
│                                                             │
└────────────────────────────────────────────────────────────┘
```

---

## 5. COST ANALYSIS

### 5.1 Monthly Cost Breakdown (Proof of Concept)

```
┌────────────────────────────────────────────────────────────┐
│ POC SCENARIO:                                             │
│ • 10 CT scans/month (1GB each) = 10GB ingested          │
│ • 1 retraining pipeline execution/week = 4/month        │
│ • Training: 25 min per execution on ml.p3.2xlarge      │
│ • Processing: 5 min per execution on ml.m5.2xlarge     │
│ • 1 radiologist user                                     │
└────────────────────────────────────────────────────────────┘

AWS HealthImaging:
  ├─ Storage: 10 GB × $40/TB/month             = $0.40
  ├─ Retrieval: 10,000 frames × $0.00005       = $0.50
  ├─ API calls: 500 calls × $0.001             = $0.50
  └─ Subtotal:                                   ~$1.40/mo

SageMaker (4 training runs/month):
  ├─ Training: 100 hours total × $3.06/hr (p3) = $306
  ├─ Processing: 20 hours total × $0.48/hr     = $9.60
  ├─ Model ops: registry, monitoring           = $5
  └─ Subtotal:                                   ~$321/mo

S3 Storage:
  ├─ Training data: 10 GB × $0.023             = $0.23
  ├─ Preprocessed: 8 GB × $0.023               = $0.18
  ├─ Models: 5 models × 500MB × $0.023         = $0.06
  ├─ Logs: 50 GB × $0.023 (tiered)             = $1.15
  └─ Subtotal:                                   ~$1.62/mo

Lambda:
  ├─ Executions: 100/month × 512MB × 300s      = $1.50
  └─ Subtotal:                                   ~$1.50/mo

DynamoDB:
  ├─ On-demand: 1000 writes + 5000 reads/mo    = $2
  └─ Subtotal:                                   ~$2/mo

CloudWatch:
  ├─ Logs ingestion: 100 GB × $0.50/GB         = $50
  ├─ Custom metrics: 20 metrics × $0.30        = $6
  ├─ Dashboards: 3 dashboards × $3             = $9
  ├─ Alarms: 10 alarms × $0.10                 = $1
  └─ Subtotal:                                   ~$66/mo

VPC/Networking:
  ├─ NAT Gateway: $32/month (2 AZs)            = $32
  ├─ Data transfer: minimal (private endpoints) = $0
  └─ Subtotal:                                   ~$32/mo

Data Transfer:
  ├─ Inbound: Free
  ├─ Outbound: 50 GB × $0.09/GB (to internet)  = $4.50
  └─ Subtotal:                                   ~$4.50/mo

KMS:
  ├─ Keys: 5 keys × $1/month                   = $5
  ├─ Operations: 100,000 calls × $0.03/10K    = $0.30
  └─ Subtotal:                                   ~$5.30/mo

TOTAL POC COST:                                  ~$434/month

┌────────────────────────────────────────────────────────────┐
│ COST OPTIMIZATION OPPORTUNITIES                          │
├────────────────────────────────────────────────────────────┤
│                                                             │
│ 1. Use Spot Instances for Training:                     │
│    • ml.p3.2xlarge Spot = ~$0.92/hr (vs $3.06)          │
│    • Savings: 70% = $214/month                           │
│    • Trade-off: Interruption possible (acceptable)       │
│                                                             │
│ 2. S3 Intelligent-Tiering:                              │
│    • Auto-moves cold data to cheaper tiers              │
│    • Savings: ~20% on storage = $0.32/month             │
│                                                             │
│ 3. Reserved Capacity:                                  │
│    • SageMaker: 1-year RI = 35% discount = $2,600/year  │
│    • Monthly equivalent: $217 (vs $321)                 │
│                                                             │
│ 4. Compress Training Data:                             │
│    • GZIP training data: 10GB → 3GB                     │
│    • Storage savings: $0.16/month                       │
│                                                             │
│ OPTIMIZED TOTAL:  ~$230-250/month (43% savings)        │
│                                                             │
└────────────────────────────────────────────────────────────┘
```

### 5.2 Scaling Costs (100 scans/month)

```
Production Scenario:
  • 100 CT scans/month (1GB each) = 100GB ingested
  • 4 retraining pipelines/week = 16/month
  • 5 radiologists concurrently
  • Real-time inference endpoints

Estimated Cost:
  • HealthImaging:                  ~$14
  • SageMaker (Spot + Reserved):    ~$2,170
  • S3:                             ~$3
  • Lambda:                         ~$15
  • DynamoDB:                       ~$20
  • CloudWatch:                     ~$150
  • VPC:                            ~$32
  • Data transfer:                  ~$45
  • KMS:                            ~$5
  ────────────────────────────────
  TOTAL:                            ~$2,454/month

Cost per CT scan:  $2,454 / 100 = $24.54 (including compute)
Without SageMaker overhead: $4.54 per scan
```

---

## 6. DEPLOYMENT CHECKLIST

- [ ] **AWS Account Setup**
  - [ ] VPC created with private subnets
  - [ ] KMS keys created and policies set
  - [ ] S3 buckets created with encryption
  - [ ] DynamoDB tables created

- [ ] **Infrastructure (Terraform)**
  - [ ] `terraform init` successful
  - [ ] `terraform plan` shows expected resources
  - [ ] `terraform apply` completes without errors
  - [ ] All outputs captured (DataStore ID, Pipeline ARN, etc.)

- [ ] **HealthImaging**
  - [ ] Data Store created and accessible
  - [ ] DICOM ingestion bucket configured
  - [ ] Pre-signed URL generation tested
  - [ ] Streaming to mobile browser verified (60fps)

- [ ] **SageMaker Pipeline**
  - [ ] Pipeline definition uploaded
  - [ ] Training/processing containers built and pushed to ECR
  - [ ] IAM roles configured with correct permissions
  - [ ] Test execution successful

- [ ] **Lambda Functions**
  - [ ] All 4 functions deployed
  - [ ] Environment variables set correctly
  - [ ] IAM roles with minimal permissions
  - [ ] CloudWatch logs verified

- [ ] **EventBridge**
  - [ ] Event bus created
  - [ ] All 5 rules configured
  - [ ] Test events published and processed

- [ ] **Monitoring**
  - [ ] CloudWatch dashboards created
  - [ ] Alarms configured with SNS topics
  - [ ] CloudTrail logging enabled
  - [ ] Log retention policies set

- [ ] **Security & Compliance**
  - [ ] HIPAA audit trail verified
  - [ ] Encryption in transit/at rest confirmed
  - [ ] VPC endpoint access only (no internet)
  - [ ] IAM policies reviewed

- [ ] **Testing**
  - [ ] Upload test DICOM file
  - [ ] Verify image ingestion
  - [ ] Test streaming to mobile browser
  - [ ] Trigger pipeline manually
  - [ ] Verify model training
  - [ ] Confirm model registration

- [ ] **Documentation**
  - [ ] Architecture diagrams reviewed
  - [ ] API documentation published
  - [ ] Runbook created for manual operations
  - [ ] Troubleshooting guide written

---

## 7. NEXT STEPS

1. **Deploy to Dev**: Complete terraform apply in development environment
2. **Validate Streaming**: Test HealthImaging streaming at 60fps with actual DICOM
3. **Trigger Pipeline**: Upload verified DICOM, confirm pipeline execution
4. **Measure Performance**: Track latency, accuracy, costs in CloudWatch
5. **Scale to Production**: Apply same infrastructure to prod environment with Reserved Capacity
6. **Implement Inference**: Deploy model endpoint for real-time diagnostic support
7. **Monitor Drift**: Implement SageMaker Model Monitor for drift detection

---

**Last Updated**: January 2026
**Status**: Production-Ready for POC
**Maintainer**: Cloud Assembly (AWS Advanced Partner)
