#!/bin/bash
# ============================================================================
# Frontend Update Script
# Healthcare Imaging MLOps Platform
# Updates frontend files in S3 and invalidates CloudFront cache
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"
FRONTEND_DIR="$PROJECT_ROOT/frontend"

echo "============================================"
echo "Frontend Update"
echo "============================================"

# Check prerequisites
command -v aws >/dev/null 2>&1 || { echo "AWS CLI required but not installed."; exit 1; }

# Get Terraform outputs
echo "Getting deployment configuration..."

FRONTEND_BUCKET=$(cd "$TERRAFORM_DIR" && terraform output -raw frontend_bucket 2>/dev/null || echo "")
DISTRIBUTION_ID=$(cd "$TERRAFORM_DIR" && terraform output -raw cloudfront_distribution_id 2>/dev/null || echo "")
FRONTEND_URL=$(cd "$TERRAFORM_DIR" && terraform output -raw frontend_url 2>/dev/null || echo "")

if [ -z "$FRONTEND_BUCKET" ]; then
    echo "Error: Could not get frontend bucket from Terraform. Run 'terraform apply' first."
    exit 1
fi

echo "Configuration:"
echo "  Frontend Bucket: $FRONTEND_BUCKET"
echo "  CloudFront Distribution: $DISTRIBUTION_ID"
echo "  Frontend URL: $FRONTEND_URL"

# Sync frontend files to S3
echo ""
echo "Uploading frontend files to S3..."
aws s3 sync "$FRONTEND_DIR/" "s3://$FRONTEND_BUCKET/" \
    --exclude "*.md" \
    --exclude ".DS_Store" \
    --delete

# Set correct content types
echo "Setting content types..."
aws s3 cp "s3://$FRONTEND_BUCKET/index.html" "s3://$FRONTEND_BUCKET/index.html" \
    --content-type "text/html" \
    --metadata-directive REPLACE

aws s3 cp "s3://$FRONTEND_BUCKET/config.js" "s3://$FRONTEND_BUCKET/config.js" \
    --content-type "application/javascript" \
    --metadata-directive REPLACE

# Invalidate CloudFront cache
if [ -n "$DISTRIBUTION_ID" ]; then
    echo ""
    echo "Invalidating CloudFront cache..."
    INVALIDATION_ID=$(aws cloudfront create-invalidation \
        --distribution-id "$DISTRIBUTION_ID" \
        --paths "/*" \
        --query 'Invalidation.Id' \
        --output text)
    echo "Invalidation ID: $INVALIDATION_ID"
fi

echo ""
echo "============================================"
echo "Frontend Update Complete!"
echo "============================================"
echo ""
echo "Frontend URL: $FRONTEND_URL"
echo ""
echo "Note: CloudFront cache invalidation may take a few minutes."
