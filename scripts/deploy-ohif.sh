#!/bin/bash
# ============================================================================
# OHIF Viewer Deployment Script
# Healthcare Imaging MLOps Platform
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
OHIF_DIR="$PROJECT_ROOT/ohif"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"

echo "============================================"
echo "OHIF Viewer Deployment"
echo "============================================"

# Check prerequisites
command -v aws >/dev/null 2>&1 || { echo "AWS CLI required but not installed."; exit 1; }
command -v terraform >/dev/null 2>&1 || { echo "Terraform required but not installed."; exit 1; }

# Get Terraform outputs
cd "$TERRAFORM_DIR"

echo "Getting deployment configuration from Terraform..."
OHIF_BUCKET=$(terraform output -raw ohif_viewer_bucket 2>/dev/null || echo "")
DISTRIBUTION_ID=$(terraform output -raw ohif_cloudfront_distribution_id 2>/dev/null || echo "")
OHIF_URL=$(terraform output -raw ohif_viewer_url 2>/dev/null || echo "")
DATASTORE_ID=$(terraform output -raw healthimaging_data_store_id 2>/dev/null || echo "")
AWS_REGION=$(terraform output -json deployment_info 2>/dev/null | jq -r '.region' || echo "us-east-1")
COGNITO_USER_POOL_ID=$(terraform output -raw cognito_user_pool_id 2>/dev/null || echo "")
COGNITO_CLIENT_ID=$(terraform output -raw cognito_client_id 2>/dev/null || echo "")
COGNITO_IDENTITY_POOL_ID=$(terraform output -raw cognito_identity_pool_id 2>/dev/null || echo "")

if [ -z "$OHIF_BUCKET" ]; then
    echo "Error: Could not get OHIF bucket from Terraform. Run 'terraform apply' first."
    exit 1
fi

echo "Configuration:"
echo "  OHIF Bucket: $OHIF_BUCKET"
echo "  CloudFront Distribution: $DISTRIBUTION_ID"
echo "  HealthImaging Datastore: $DATASTORE_ID"
echo "  Region: $AWS_REGION"

# Check if OHIF source exists
OHIF_SOURCE="$PROJECT_ROOT/ohif-source"
if [ ! -d "$OHIF_SOURCE" ]; then
    echo ""
    echo "OHIF source not found. Cloning..."
    cd "$PROJECT_ROOT"
    git clone --depth 1 https://github.com/OHIF/Viewers.git ohif-source
    cd "$OHIF_SOURCE"
    yarn install
fi

# Generate OHIF configuration
echo ""
echo "Generating OHIF configuration..."

COGNITO_DOMAIN="${OHIF_BUCKET%-ohif-viewer-*}-${COGNITO_USER_POOL_ID##*_}"
COGNITO_DOMAIN=$(echo "$COGNITO_DOMAIN" | tr '[:upper:]' '[:lower:]')

cat > "$OHIF_SOURCE/platform/app/public/config/healthimaging.js" << EOF
window.config = {
  routerBasename: '/',
  
  // AWS HealthImaging data source
  dataSources: [
    {
      namespace: '@ohif/extension-default.dataSourcesModule.healthimaging',
      sourceName: 'healthimaging',
      configuration: {
        name: 'AWS HealthImaging',
        datastoreID: '${DATASTORE_ID}',
        region: '${AWS_REGION}',
        
        // Cognito authentication
        authConfig: {
          type: 'cognito',
          region: '${AWS_REGION}',
          userPoolId: '${COGNITO_USER_POOL_ID}',
          userPoolWebClientId: '${COGNITO_CLIENT_ID}',
          identityPoolId: '${COGNITO_IDENTITY_POOL_ID}',
          oauth: {
            domain: '${COGNITO_DOMAIN}.auth.${AWS_REGION}.amazoncognito.com',
            scope: ['email', 'openid', 'profile', 'aws.cognito.signin.user.admin'],
            redirectSignIn: '${OHIF_URL}/callback',
            redirectSignOut: '${OHIF_URL}/',
            responseType: 'code'
          }
        }
      },
    },
  ],
  
  defaultDataSourceName: 'healthimaging',
  
  // Extensions
  extensions: [
    '@ohif/extension-default',
    '@ohif/extension-cornerstone',
    '@ohif/extension-measurement-tracking',
    '@ohif/extension-cornerstone-dicom-sr',
  ],
  
  // Modes
  modes: [
    '@ohif/mode-longitudinal',
    '@ohif/mode-basic-dev-mode',
  ],
  
  showStudyList: true,
  maxNumberOfWebWorkers: 4,
  showWarningMessageForCrossOrigin: false,
  strictZoomAndPan: false,
  
  // Disable investigational use dialog
  investigationalUseDialog: {
    option: 'never',
  },
  
  // Custom branding
  whiteLabeling: {
    createLogoComponentFn: function() {
      return null;
    },
  },
};
EOF

echo "Configuration generated at: $OHIF_SOURCE/platform/app/public/config/healthimaging.js"

# Build OHIF
echo ""
echo "Building OHIF Viewer..."
cd "$OHIF_SOURCE"
APP_CONFIG=config/healthimaging.js yarn build

# Deploy to S3
echo ""
echo "Deploying to S3..."
aws s3 sync platform/app/dist/ "s3://$OHIF_BUCKET/" --delete

# Invalidate CloudFront cache
if [ -n "$DISTRIBUTION_ID" ]; then
    echo ""
    echo "Invalidating CloudFront cache..."
    aws cloudfront create-invalidation \
        --distribution-id "$DISTRIBUTION_ID" \
        --paths "/*" \
        --output text
fi

echo ""
echo "============================================"
echo "OHIF Viewer Deployment Complete!"
echo "============================================"
echo ""
echo "Viewer URL: $OHIF_URL"
echo ""
echo "Note: CloudFront cache invalidation may take a few minutes."
