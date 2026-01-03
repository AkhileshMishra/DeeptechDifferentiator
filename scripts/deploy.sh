#!/bin/bash
# Healthcare Imaging MLOps Platform - Deployment Script
# This script orchestrates the complete deployment process

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="${PROJECT_ROOT}/terraform"
DOCKER_DIR="${PROJECT_ROOT}/docker"

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check Terraform
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform is not installed. Please install it first."
        exit 1
    fi
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install it first."
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials are not configured. Please run 'aws configure'."
        exit 1
    fi
    
    log_info "All prerequisites met."
}

deploy_infrastructure() {
    log_info "Deploying infrastructure with Terraform..."
    
    cd "${TERRAFORM_DIR}"
    
    # Initialize Terraform
    terraform init
    
    # Plan deployment
    terraform plan -out=tfplan
    
    # Apply deployment
    terraform apply tfplan
    
    # Save outputs
    terraform output -json > deployment-outputs.json
    
    log_info "Infrastructure deployment complete."
}

build_docker_images() {
    log_info "Building Docker images..."
    
    # Get AWS account ID and region
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    AWS_REGION=$(aws configure get region)
    
    # ECR login
    aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
    
    # Build and push each container
    for container in preprocessing training evaluation inference; do
        log_info "Building ${container} container..."
        
        cd "${DOCKER_DIR}/sagemaker/${container}"
        
        IMAGE_NAME="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/healthcare-imaging-mlops-${container}:latest"
        
        docker build -t ${IMAGE_NAME} .
        docker push ${IMAGE_NAME}
        
        log_info "${container} container pushed to ECR."
    done
    
    log_info "All Docker images built and pushed."
}

validate_deployment() {
    log_info "Validating deployment..."
    
    "${SCRIPT_DIR}/validate-deployment.sh"
    
    log_info "Deployment validation complete."
}

print_summary() {
    log_info "Deployment Summary"
    echo "===================="
    
    cd "${TERRAFORM_DIR}"
    
    echo ""
    echo "VPC ID: $(terraform output -raw vpc_id 2>/dev/null || echo 'N/A')"
    echo "HealthImaging Datastore: $(terraform output -raw healthimaging_datastore_id 2>/dev/null || echo 'N/A')"
    echo "SageMaker Pipeline: $(terraform output -raw sagemaker_pipeline_arn 2>/dev/null || echo 'N/A')"
    echo "Training Bucket: $(terraform output -raw training_data_bucket 2>/dev/null || echo 'N/A')"
    echo ""
    
    log_info "Deployment complete! See deployment-outputs.json for full details."
}

# Main execution
main() {
    log_info "Starting Healthcare Imaging MLOps Platform deployment..."
    
    check_prerequisites
    deploy_infrastructure
    build_docker_images
    validate_deployment
    print_summary
}

# Run main function
main "$@"
