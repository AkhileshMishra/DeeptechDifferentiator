# Healthcare Imaging MLOps Repository
## Module 3: Rapid Remote Triage & Continuous Model Improvement
### AWS HealthImaging + SageMaker Pipelines Integration

---

## Repository Structure

```
healthcare-imaging-mlops/
│
├── README.md                           # Project overview & quick start
├── ARCHITECTURE.md                     # Detailed system architecture
├── DEPLOYMENT.md                       # Step-by-step deployment guide
│
├── terraform/                          # Infrastructure as Code (Terraform)
│   ├── main.tf                         # Main Terraform configuration
│   ├── variables.tf                    # Variable definitions
│   ├── outputs.tf                      # Output definitions
│   ├── terraform.tfvars.example        # Example terraform variables
│   │
│   ├── modules/
│   │   ├── healthimaging/              # AWS HealthImaging setup
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   ├── outputs.tf
│   │   │   ├── iam.tf                  # IAM roles and policies
│   │   │   └── security.tf             # Security groups, KMS
│   │   │
│   │   ├── sagemaker/                  # SageMaker Pipeline setup
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   ├── outputs.tf
│   │   │   ├── iam.tf                  # SageMaker execution roles
│   │   │   └── pipeline.tf             # Pipeline orchestration
│   │   │
│   │   ├── networking/                 # VPC, subnets, endpoints
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   │
│   │   ├── storage/                    # S3 buckets for training data
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   ├── outputs.tf
│   │   │   └── lifecycle.tf            # Retention policies
│   │   │
│   │   ├── eventbridge/                # Event-driven automation
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   ├── outputs.tf
│   │   │   └── rules.tf                # Event rules for triggers
│   │   │
│   │   ├── lambda/                     # Lambda functions
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── outputs.tf
│   │   │
│   │   ├── ecr/                        # Docker registry
│   │   │   ├── main.tf
│   │   │   └── variables.tf
│   │   │
│   │   ├── monitoring/                 # CloudWatch, alarms
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── dashboards.tf
│   │   │
│   │   └── security/                   # KMS, secrets manager
│   │       ├── main.tf
│   │       └── variables.tf
│   │
│   └── environments/
│       ├── dev.tfvars                  # Development environment
│       ├── staging.tfvars              # Staging environment
│       └── prod.tfvars                 # Production environment
│
├── cloudformation/                     # Alternative CloudFormation templates
│   ├── master-stack.yaml               # Master stack (orchestrates all)
│   ├── healthimaging-stack.yaml        # HealthImaging resources
│   ├── sagemaker-stack.yaml            # SageMaker resources
│   ├── eventbridge-stack.yaml          # Event automation
│   └── networking-stack.yaml           # VPC and networking
│
├── python/                             # Python code for ML pipeline
│   ├── src/
│   │   ├── __init__.py
│   │   │
│   │   ├── pipeline/
│   │   │   ├── __init__.py
│   │   │   ├── preprocessing.py        # Data preprocessing steps
│   │   │   ├── training.py             # Model training script
│   │   │   ├── evaluation.py           # Model evaluation
│   │   │   ├── inference.py            # Batch inference
│   │   │   └── pipeline_builder.py     # SageMaker Pipeline definition
│   │   │
│   │   ├── healthimaging/
│   │   │   ├── __init__.py
│   │   │   ├── client.py               # HealthImaging API client
│   │   │   ├── dicom_handler.py        # DICOM file processing
│   │   │   └── image_retrieval.py      # Image streaming logic
│   │   │
│   │   ├── ml_model/
│   │   │   ├── __init__.py
│   │   │   ├── pneumonia_detector.py   # Pneumonia detection model
│   │   │   ├── model_utils.py          # Model utility functions
│   │   │   └── model_config.py         # Model configuration
│   │   │
│   │   ├── lambda_handlers/
│   │   │   ├── __init__.py
│   │   │   ├── image_ingestion.py      # Triggered on image upload
│   │   │   ├── pipeline_trigger.py     # Triggers SageMaker pipeline
│   │   │   ├── model_deployment.py     # Deploys new models
│   │   │   └── monitoring.py           # Health checks
│   │   │
│   │   ├── utils/
│   │   │   ├── __init__.py
│   │   │   ├── aws_clients.py          # Boto3 client factory
│   │   │   ├── logging_config.py       # Logging setup
│   │   │   ├── config.py               # Configuration management
│   │   │   └── exceptions.py           # Custom exceptions
│   │   │
│   │   └── api/
│   │       ├── __init__.py
│   │       ├── app.py                  # FastAPI/Flask application
│   │       ├── routes.py               # API endpoints
│   │       ├── schemas.py              # Request/response models
│   │       └── security.py             # Authentication & authorization
│   │
│   ├── tests/
│   │   ├── __init__.py
│   │   ├── conftest.py                 # Pytest configuration
│   │   ├── unit/
│   │   │   ├── test_dicom_handler.py
│   │   │   ├── test_preprocessing.py
│   │   │   └── test_model.py
│   │   └── integration/
│   │       ├── test_healthimaging_integration.py
│   │       ├── test_sagemaker_pipeline.py
│   │       └── test_end_to_end.py
│   │
│   ├── notebooks/
│   │   ├── 01-data-exploration.ipynb
│   │   ├── 02-model-development.ipynb
│   │   ├── 03-pipeline-testing.ipynb
│   │   └── 04-deployment-validation.ipynb
│   │
│   ├── docker/
│   │   ├── preprocessing.dockerfile
│   │   ├── training.dockerfile
│   │   ├── evaluation.dockerfile
│   │   ├── inference.dockerfile
│   │   └── api.dockerfile
│   │
│   ├── requirements.txt                # Python dependencies
│   ├── setup.py                        # Package setup
│   └── pyproject.toml                  # Project metadata
│
├── docker/                             # Docker configurations
│   ├── sagemaker/
│   │   ├── preprocessing/
│   │   │   └── Dockerfile
│   │   ├── training/
│   │   │   └── Dockerfile
│   │   ├── evaluation/
│   │   │   └── Dockerfile
│   │   └── inference/
│   │       └── Dockerfile
│   │
│   └── api/
│       └── Dockerfile                  # REST API container
│
├── helm/                               # Kubernetes Helm charts (optional)
│   ├── imaging-api-chart/
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │
│   └── monitoring-chart/
│       ├── Chart.yaml
│       └── values.yaml
│
├── scripts/
│   ├── setup.sh                        # Initial setup script
│   ├── deploy.sh                       # Deployment orchestration
│   ├── test.sh                         # Run tests
│   ├── generate-sample-dicom.py        # Generate test DICOM files
│   ├── validate-deployment.sh          # Post-deployment validation
│   ├── cleanup.sh                      # Clean up resources
│   └── monitoring/
│       ├── setup-dashboards.py         # CloudWatch dashboards
│       └── setup-alarms.py             # CloudWatch alarms
│
├── docs/
│   ├── API.md                          # API documentation
│   ├── DICOM_STREAMING.md              # HealthImaging streaming guide
│   ├── MLOPS_PIPELINE.md               # SageMaker pipeline guide
│   ├── COMPLIANCE.md                   # HIPAA/compliance considerations
│   ├── TROUBLESHOOTING.md              # Troubleshooting guide
│   └── COST_OPTIMIZATION.md            # Cost optimization tips
│
├── config/
│   ├── pipeline-config.yaml            # Pipeline parameters
│   ├── model-config.yaml               # Model hyperparameters
│   ├── logging-config.yaml             # Logging configuration
│   └── security-policies.yaml          # Security policies
│
├── .github/
│   └── workflows/
│       ├── deploy-dev.yml              # CI/CD for dev
│       ├── deploy-staging.yml          # CI/CD for staging
│       ├── deploy-prod.yml             # CI/CD for prod
│       ├── test.yml                    # Automated testing
│       └── security-scan.yml           # Security scanning
│
├── .gitignore
├── .dockerignore
├── Makefile                            # Development commands
└── LICENSE
```

---

## Quick Start (5 Minutes)

### Prerequisites
- AWS Account with appropriate IAM permissions
- Terraform >= 1.0
- AWS CLI v2 configured
- Docker (for local testing)
- Python 3.9+

### Deploy to AWS

```bash
# 1. Clone and setup
git clone <repo-url>
cd healthcare-imaging-mlops

# 2. Configure environment
cp terraform/environments/dev.tfvars terraform/terraform.tfvars
# Edit terraform.tfvars with your values

# 3. Initialize and deploy
cd terraform
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# 4. Verify deployment
../scripts/validate-deployment.sh

# 5. Access the system
terraform output -json > deployment-info.json
```

---

## Core Architecture Components

### 1. AWS HealthImaging Module
**Purpose**: Zero-latency streaming of 1GB+ DICOM files

**Key Resources**:
- HealthImaging Data Store
- HTJ2K Compression (40% cost savings)
- S3 Integration for DICOM ingestion
- IAM roles for secure access
- KMS encryption at rest

**Outputs**:
- HealthImaging Data Store ID
- Streaming endpoint URL
- S3 ingestion bucket

### 2. SageMaker Pipelines Module
**Purpose**: Automated training CI/CD triggered by new data

**Key Resources**:
- SageMaker Pipeline definition
- Processing jobs (preprocessing)
- Training job (pneumonia detection)
- Evaluation step
- Model registry integration
- Execution role with proper permissions

**Outputs**:
- Pipeline ARN
- Model artifact location
- Training metrics

### 3. EventBridge Module
**Purpose**: Orchestration and automation

**Rules**:
- **Rule 1**: "ImageVerified" → Trigger SageMaker pipeline
- **Rule 2**: "ModelTrainingComplete" → Run evaluation
- **Rule 3**: "EvaluationPassed" → Register model
- **Rule 4**: "AlertingRuleViolation" → Notify team

### 4. Lambda Functions
**Purpose**: Serverless event handlers

**Functions**:
1. `ImageIngestionHandler`: Processes uploaded DICOM files
2. `PipelineTrigger`: Initiates SageMaker pipeline
3. `ModelDeploymentHandler`: Deploys validated models
4. `MonitoringHandler`: Health checks and metrics

### 5. Storage Layer
**Purpose**: Data management and artifacts

**S3 Buckets**:
- `training-data-<account>`: Raw DICOM files
- `preprocessed-data-<account>`: Preprocessed datasets
- `model-artifacts-<account>`: Trained models
- `logs-<account>`: Pipeline logs

### 6. Monitoring & Logging
**Purpose**: Observability and compliance

**Components**:
- CloudWatch Logs for all services
- CloudWatch Metrics for pipeline performance
- CloudWatch Dashboards for real-time monitoring
- SNS alerts for critical failures
- VPC Flow Logs for security audit

---

## Deployment Workflows

### Development Deployment
```bash
# Deploy to development environment
make deploy-dev

# Run tests
make test

# Validate
make validate

# Cleanup (if needed)
make cleanup-dev
```

### Production Deployment
```bash
# Run security scan
make security-scan

# Plan production changes
make plan-prod

# Deploy to production
make deploy-prod

# Run smoke tests
make smoke-test-prod

# Monitor deployment
make monitor-prod
```

---

## Security & Compliance

### HIPAA Compliance
- ✓ Data encryption at rest (KMS)
- ✓ Data encryption in transit (TLS 1.2+)
- ✓ VPC endpoints (no internet exposure)
- ✓ Audit logging (CloudTrail, VPC Flow Logs)
- ✓ Access controls (IAM, resource-based policies)
- ✓ Data retention policies
- ✓ Incident response procedures

### Security Best Practices
- All S3 buckets have versioning enabled
- All resources encrypted with customer-managed KMS keys
- Least privilege IAM policies
- VPC isolation with security groups
- No public endpoints (private by default)
- Secrets management via AWS Secrets Manager
- Network access logging enabled

---

## Cost Optimization

### Expected Monthly Costs (Proof of Concept)
- **HealthImaging Storage**: ~$40 (1TB @ $40/TB with 40% HTJ2K savings)
- **SageMaker Training**: ~$100 (10 hours/month on ml.p3.2xlarge)
- **S3 Storage**: ~$20 (100GB standard storage)
- **Lambda**: ~$5 (100K invocations)
- **Data Transfer**: ~$10
- **CloudWatch**: ~$10
- **Total**: ~$185/month

### Scaling Considerations
- Auto-scaling training instances based on queue depth
- S3 Intelligent-Tiering for long-term data
- Spot instances for training jobs (up to 70% savings)
- Reserved capacity for baseline workloads

---

## Testing

### Unit Tests
```bash
cd python
pytest tests/unit/
```

### Integration Tests
```bash
pytest tests/integration/
```

### End-to-End Tests
```bash
pytest tests/integration/test_end_to_end.py
```

### Load Testing
```bash
# Test HealthImaging streaming at scale
python tests/load/test_streaming_performance.py
```

---

## Support & Documentation

- **Architecture**: See `ARCHITECTURE.md`
- **Deployment**: See `DEPLOYMENT.md`
- **API Documentation**: See `docs/API.md`
- **DICOM Streaming**: See `docs/DICOM_STREAMING.md`
- **MLOps Pipeline**: See `docs/MLOPS_PIPELINE.md`
- **Troubleshooting**: See `docs/TROUBLESHOOTING.md`

---

## License

MIT License - See LICENSE file

---

## Contributing

See CONTRIBUTING.md for guidelines

---

## Workshop Context

This repository implements Module 3 of the AWS HealthTech Accelerator Workshop:
- **Theme**: High-Speed Streaming & Automated Training
- **Demo Duration**: 45 minutes
- **Key Value**: Zero-latency DICOM streaming + automated MLOps
- **Cost Reduction**: 40% via HTJ2K compression vs. standard S3

**Workshop Deliverables**:
1. ✅ Stream 1GB Chest CT Scan over 4G at 60fps
2. ✅ Mobile browser viewing without download
3. ✅ Automated pipeline trigger on image verification
4. ✅ Continuous model improvement without manual intervention

---

**Last Updated**: January 2026
**Status**: Production-Ready
**Maintainer**: Cloud Assembly (AWS Advanced Partner)
