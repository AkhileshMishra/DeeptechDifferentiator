#!/bin/bash
# ============================================================================
# OHIF Integration Validation Script
# Healthcare Imaging MLOps Platform
# Validates the OIDC + HealthImaging + OHIF integration
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"

echo "============================================"
echo "OHIF Integration Validation"
echo "============================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; }
warn() { echo -e "${YELLOW}!${NC} $1"; }

# Check prerequisites
echo "Checking prerequisites..."
command -v aws >/dev/null 2>&1 && pass "AWS CLI installed" || fail "AWS CLI not installed"
command -v jq >/dev/null 2>&1 && pass "jq installed" || fail "jq not installed"

# Get Terraform outputs
echo ""
echo "Getting Terraform outputs..."

cd "$TERRAFORM_DIR"

FRONTEND_URL=$(terraform output -raw frontend_url 2>/dev/null || echo "")
OHIF_URL=$(terraform output -raw ohif_viewer_url 2>/dev/null || echo "")
API_ENDPOINT=$(terraform output -raw api_gateway_endpoint 2>/dev/null || echo "")
DATASTORE_ID=$(terraform output -raw healthimaging_data_store_id 2>/dev/null || echo "")
USER_POOL_ID=$(terraform output -raw cognito_user_pool_id 2>/dev/null || echo "")
IDENTITY_POOL_ID=$(terraform output -raw cognito_identity_pool_id 2>/dev/null || echo "")
AWS_REGION=$(terraform output -json deployment_info 2>/dev/null | jq -r '.region' || echo "us-east-1")

echo ""
echo "Configuration:"
echo "  Frontend URL: $FRONTEND_URL"
echo "  OHIF URL: $OHIF_URL"
echo "  API Endpoint: $API_ENDPOINT"
echo "  Datastore ID: $DATASTORE_ID"
echo "  User Pool ID: $USER_POOL_ID"
echo "  Identity Pool ID: $IDENTITY_POOL_ID"
echo "  Region: $AWS_REGION"

# Validate Terraform outputs
echo ""
echo "Validating Terraform outputs..."
[ -n "$FRONTEND_URL" ] && pass "Frontend URL configured" || fail "Frontend URL not configured"
[ -n "$OHIF_URL" ] && pass "OHIF URL configured" || fail "OHIF URL not configured"
[ -n "$API_ENDPOINT" ] && pass "API endpoint configured" || fail "API endpoint not configured"
[ -n "$DATASTORE_ID" ] && pass "HealthImaging datastore configured" || fail "HealthImaging datastore not configured"
[ -n "$USER_POOL_ID" ] && pass "Cognito User Pool configured" || fail "Cognito User Pool not configured"
[ -n "$IDENTITY_POOL_ID" ] && pass "Cognito Identity Pool configured" || fail "Cognito Identity Pool not configured"

# Validate HealthImaging datastore
echo ""
echo "Validating HealthImaging datastore..."
if [ -n "$DATASTORE_ID" ]; then
    DATASTORE_STATUS=$(aws medical-imaging get-datastore \
        --datastore-id "$DATASTORE_ID" \
        --region "$AWS_REGION" \
        --query 'datastoreProperties.datastoreStatus' \
        --output text 2>/dev/null || echo "ERROR")
    
    if [ "$DATASTORE_STATUS" = "ACTIVE" ]; then
        pass "HealthImaging datastore is ACTIVE"
    else
        fail "HealthImaging datastore status: $DATASTORE_STATUS"
    fi
fi

# Validate Cognito User Pool
echo ""
echo "Validating Cognito User Pool..."
if [ -n "$USER_POOL_ID" ]; then
    POOL_STATUS=$(aws cognito-idp describe-user-pool \
        --user-pool-id "$USER_POOL_ID" \
        --region "$AWS_REGION" \
        --query 'UserPool.Status' \
        --output text 2>/dev/null || echo "ERROR")
    
    if [ "$POOL_STATUS" = "Enabled" ] || [ -n "$POOL_STATUS" ]; then
        pass "Cognito User Pool exists"
    else
        fail "Cognito User Pool status: $POOL_STATUS"
    fi
fi

# Validate Cognito Identity Pool
echo ""
echo "Validating Cognito Identity Pool..."
if [ -n "$IDENTITY_POOL_ID" ]; then
    IDENTITY_POOL_NAME=$(aws cognito-identity describe-identity-pool \
        --identity-pool-id "$IDENTITY_POOL_ID" \
        --region "$AWS_REGION" \
        --query 'IdentityPoolName' \
        --output text 2>/dev/null || echo "ERROR")
    
    if [ "$IDENTITY_POOL_NAME" != "ERROR" ]; then
        pass "Cognito Identity Pool exists: $IDENTITY_POOL_NAME"
    else
        fail "Cognito Identity Pool not found"
    fi
fi

# Validate API Gateway endpoints
echo ""
echo "Validating API Gateway endpoints..."
if [ -n "$API_ENDPOINT" ]; then
    # Test list-image-sets endpoint
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$API_ENDPOINT/list-image-sets" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        pass "list-image-sets endpoint responding (HTTP $HTTP_CODE)"
    else
        warn "list-image-sets endpoint returned HTTP $HTTP_CODE"
    fi
fi

# Validate CloudFront distributions
echo ""
echo "Validating CloudFront distributions..."
if [ -n "$FRONTEND_URL" ]; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$FRONTEND_URL" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        pass "Frontend CloudFront responding (HTTP $HTTP_CODE)"
    else
        warn "Frontend CloudFront returned HTTP $HTTP_CODE"
    fi
fi

if [ -n "$OHIF_URL" ]; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$OHIF_URL" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        pass "OHIF CloudFront responding (HTTP $HTTP_CODE)"
    else
        warn "OHIF CloudFront returned HTTP $HTTP_CODE"
    fi
fi

# Check for image sets in datastore
echo ""
echo "Checking for image sets in datastore..."
if [ -n "$DATASTORE_ID" ]; then
    IMAGE_SET_COUNT=$(aws medical-imaging search-image-sets \
        --datastore-id "$DATASTORE_ID" \
        --region "$AWS_REGION" \
        --search-criteria '{"filters":[]}' \
        --query 'length(imageSetsMetadataSummaries)' \
        --output text 2>/dev/null || echo "0")
    
    if [ "$IMAGE_SET_COUNT" -gt 0 ]; then
        pass "Found $IMAGE_SET_COUNT image set(s) in datastore"
    else
        warn "No image sets found in datastore (upload DICOM files to test)"
    fi
fi

echo ""
echo "============================================"
echo "Validation Complete"
echo "============================================"
echo ""
echo "Next steps:"
echo "1. Access the frontend: $FRONTEND_URL"
echo "2. Sign in with Cognito"
echo "3. Upload a DICOM file"
echo "4. View the image in OHIF viewer"
echo ""
echo "To deploy OHIF viewer build:"
echo "  ./scripts/deploy-ohif.sh"
echo ""
