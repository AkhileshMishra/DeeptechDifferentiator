#!/bin/bash
# Deploy HealthImaging Proxy to ECR and update ECS service

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Get configuration from Terraform
cd "$PROJECT_ROOT/terraform"
ECR_REPO=$(terraform output -raw healthimaging_ecr_repository_url 2>/dev/null || echo "")
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "us-east-1")
CLUSTER_NAME=$(terraform output -raw healthimaging_cluster_name 2>/dev/null || echo "")
SERVICE_NAME=$(terraform output -raw healthimaging_service_name 2>/dev/null || echo "")

if [ -z "$ECR_REPO" ]; then
    echo "Error: Could not get ECR repository URL from Terraform outputs"
    echo "Make sure you have run 'terraform apply' first"
    exit 1
fi

echo "=== Deploying HealthImaging Proxy ==="
echo "ECR Repository: $ECR_REPO"
echo "Region: $AWS_REGION"

# Login to ECR
echo "Logging in to ECR..."
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR_REPO"

# Build and push Docker image
echo "Building Docker image..."
cd "$PROJECT_ROOT/docker/healthimaging-proxy"
docker build -t healthimaging-proxy .

echo "Tagging image..."
docker tag healthimaging-proxy:latest "$ECR_REPO:latest"

echo "Pushing to ECR..."
docker push "$ECR_REPO:latest"

# Update ECS service to force new deployment
if [ -n "$CLUSTER_NAME" ] && [ -n "$SERVICE_NAME" ]; then
    echo "Updating ECS service..."
    aws ecs update-service \
        --cluster "$CLUSTER_NAME" \
        --service "$SERVICE_NAME" \
        --force-new-deployment \
        --region "$AWS_REGION"
    
    echo "Waiting for service to stabilize..."
    aws ecs wait services-stable \
        --cluster "$CLUSTER_NAME" \
        --services "$SERVICE_NAME" \
        --region "$AWS_REGION"
fi

echo "=== Deployment complete ==="
