#!/bin/bash
# Healthcare Imaging MLOps Platform - Deployment Validation Script
# Validates that all components are properly deployed and functional

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="${PROJECT_ROOT}/terraform"

# Validation counters
PASSED=0
FAILED=0

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((PASSED++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((FAILED++))
}

log_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

# Load Terraform outputs
load_outputs() {
    cd "${TERRAFORM_DIR}"
    if [ -f "deployment-outputs.json" ]; then
        OUTPUTS=$(cat deployment-outputs.json)
    else
        log_fail "deployment-outputs.json not found. Run deploy.sh first."
        exit 1
    fi
}

# Validate VPC
validate_vpc() {
    log_info "Validating VPC..."
    
    VPC_ID=$(echo $OUTPUTS | jq -r '.vpc_id.value // empty')
    
    if [ -n "$VPC_ID" ]; then
        VPC_STATE=$(aws ec2 describe-vpcs --vpc-ids $VPC_ID --query 'Vpcs[0].State' --output text 2>/dev/null)
        if [ "$VPC_STATE" == "available" ]; then
            log_pass "VPC $VPC_ID is available"
        else
            log_fail "VPC $VPC_ID state: $VPC_STATE"
        fi
    else
        log_fail "VPC ID not found in outputs"
    fi
}

# Validate S3 Buckets
validate_s3_buckets() {
    log_info "Validating S3 buckets..."
    
    for bucket_key in training_data_bucket preprocessed_bucket model_artifacts_bucket; do
        BUCKET=$(echo $OUTPUTS | jq -r ".${bucket_key}.value // empty")
        
        if [ -n "$BUCKET" ]; then
            if aws s3api head-bucket --bucket $BUCKET 2>/dev/null; then
                log_pass "S3 bucket $BUCKET exists"
            else
                log_fail "S3 bucket $BUCKET not accessible"
            fi
        else
            log_info "Bucket $bucket_key not found in outputs (may be optional)"
        fi
    done
}

# Validate DynamoDB Tables
validate_dynamodb() {
    log_info "Validating DynamoDB tables..."
    
    for table_key in image_metadata_table training_metrics_table pipeline_state_table; do
        TABLE=$(echo $OUTPUTS | jq -r ".${table_key}.value // empty")
        
        if [ -n "$TABLE" ]; then
            TABLE_STATUS=$(aws dynamodb describe-table --table-name $TABLE --query 'Table.TableStatus' --output text 2>/dev/null)
            if [ "$TABLE_STATUS" == "ACTIVE" ]; then
                log_pass "DynamoDB table $TABLE is active"
            else
                log_fail "DynamoDB table $TABLE status: $TABLE_STATUS"
            fi
        else
            log_info "Table $table_key not found in outputs (may be optional)"
        fi
    done
}

# Validate Lambda Functions
validate_lambda() {
    log_info "Validating Lambda functions..."
    
    for func_key in image_ingestion_function pipeline_trigger_function model_evaluation_function; do
        FUNC=$(echo $OUTPUTS | jq -r ".${func_key}.value // empty")
        
        if [ -n "$FUNC" ]; then
            FUNC_STATE=$(aws lambda get-function --function-name $FUNC --query 'Configuration.State' --output text 2>/dev/null)
            if [ "$FUNC_STATE" == "Active" ]; then
                log_pass "Lambda function $FUNC is active"
            else
                log_fail "Lambda function $FUNC state: $FUNC_STATE"
            fi
        else
            log_info "Function $func_key not found in outputs (may be optional)"
        fi
    done
}

# Validate SageMaker Pipeline
validate_sagemaker() {
    log_info "Validating SageMaker pipeline..."
    
    PIPELINE_ARN=$(echo $OUTPUTS | jq -r '.sagemaker_pipeline_arn.value // empty')
    
    if [ -n "$PIPELINE_ARN" ]; then
        PIPELINE_STATUS=$(aws sagemaker describe-pipeline --pipeline-name $(echo $PIPELINE_ARN | awk -F'/' '{print $NF}') --query 'PipelineStatus' --output text 2>/dev/null)
        if [ "$PIPELINE_STATUS" == "Active" ]; then
            log_pass "SageMaker pipeline is active"
        else
            log_fail "SageMaker pipeline status: $PIPELINE_STATUS"
        fi
    else
        log_info "SageMaker pipeline not found in outputs (may be optional)"
    fi
}

# Validate HealthImaging Datastore
validate_healthimaging() {
    log_info "Validating HealthImaging datastore..."
    
    DATASTORE_ID=$(echo $OUTPUTS | jq -r '.healthimaging_datastore_id.value // empty')
    
    if [ -n "$DATASTORE_ID" ]; then
        DATASTORE_STATUS=$(aws medical-imaging get-datastore --datastore-id $DATASTORE_ID --query 'datastoreProperties.datastoreStatus' --output text 2>/dev/null)
        if [ "$DATASTORE_STATUS" == "ACTIVE" ]; then
            log_pass "HealthImaging datastore is active"
        else
            log_fail "HealthImaging datastore status: $DATASTORE_STATUS"
        fi
    else
        log_info "HealthImaging datastore not found in outputs (may be optional)"
    fi
}

# Validate ECR Repositories
validate_ecr() {
    log_info "Validating ECR repositories..."
    
    for repo in preprocessing training evaluation inference; do
        REPO_NAME="healthcare-imaging-mlops-${repo}"
        
        if aws ecr describe-repositories --repository-names $REPO_NAME &>/dev/null; then
            log_pass "ECR repository $REPO_NAME exists"
        else
            log_info "ECR repository $REPO_NAME not found (may need to be created)"
        fi
    done
}

# Print summary
print_summary() {
    echo ""
    echo "=========================================="
    echo "Validation Summary"
    echo "=========================================="
    echo -e "${GREEN}Passed: $PASSED${NC}"
    echo -e "${RED}Failed: $FAILED${NC}"
    echo ""
    
    if [ $FAILED -eq 0 ]; then
        echo -e "${GREEN}All validations passed!${NC}"
        exit 0
    else
        echo -e "${RED}Some validations failed. Please review the output above.${NC}"
        exit 1
    fi
}

# Main execution
main() {
    echo "Healthcare Imaging MLOps Platform - Deployment Validation"
    echo "=========================================="
    echo ""
    
    load_outputs
    validate_vpc
    validate_s3_buckets
    validate_dynamodb
    validate_lambda
    validate_sagemaker
    validate_healthimaging
    validate_ecr
    print_summary
}

main "$@"
