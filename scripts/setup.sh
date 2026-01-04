#!/bin/bash
echo "=== DeepTech Workshop Setup ==="

# 1. Python Dependencies
echo "[1/3] Installing Python dependencies..."
pip install -r python/requirements.txt
pip install boto3 pydicom numpy requests

# 2. Create Dummy Directories (Fixing Gap 1 & 5 folder structure issues)
echo "[2/3] Ensuring directory structure..."
mkdir -p python/src/lambda_handlers/mime_extractor
mkdir -p python/src/lambda_handlers/fhir_ingest
mkdir -p python/src/lambda_handlers/document_router
mkdir -p python/src/lambda_handlers/bedrock_guardrail
mkdir -p python/src/lambda_handlers/content_splitter
mkdir -p python/src/statemachine

# Create dummy handlers to satisfy Terraform if files are missing
touch python/src/lambda_handlers/mime_extractor/handler.py
touch python/src/lambda_handlers/fhir_ingest/handler.py
touch python/src/lambda_handlers/document_router/handler.py
touch python/src/lambda_handlers/bedrock_guardrail/handler.py
touch python/src/lambda_handlers/content_splitter/handler.py

# 3. Generate Test Data (Fixing Gap 10)
echo "[3/3] Generating sample DICOM data..."
python scripts/generate_sample_dicom.py sample-scan.dcm

echo "✅ Setup Complete. Run 'cd terraform && terraform apply' to deploy."
