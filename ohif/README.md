# OHIF Viewer Deployment for AWS HealthImaging

This directory contains configuration for deploying OHIF Viewer with AWS HealthImaging integration.

## Overview

The OHIF Viewer is configured to:
- Connect directly to AWS HealthImaging via the HealthImaging adapter
- Authenticate users via Amazon Cognito (OIDC)
- Decode HTJ2K frames using OpenJPH WASM
- Stream medical images with zero-latency

## Prerequisites

- Node.js 18+ and Yarn
- AWS CLI configured
- Terraform deployed (provides Cognito and HealthImaging configuration)

## Build Instructions

### 1. Clone OHIF Viewer

```bash
git clone https://github.com/OHIF/Viewers.git ohif-source
cd ohif-source
yarn install
```

### 2. Configure for HealthImaging

Copy the generated configuration:

```bash
cp ../app-config.js platform/app/public/config/default.js
```

Or create a custom configuration file `platform/app/public/config/healthimaging.js`:

```javascript
window.config = {
  routerBasename: '/',
  
  // HealthImaging data source
  dataSources: [
    {
      namespace: '@ohif/extension-default.dataSourcesModule.healthimaging',
      sourceName: 'healthimaging',
      configuration: {
        name: 'AWS HealthImaging',
        // These values come from Terraform outputs
        datastoreID: 'YOUR_DATASTORE_ID',
        region: 'us-east-1',
      },
    },
  ],
  
  defaultDataSourceName: 'healthimaging',
  
  // Extensions for HealthImaging
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
  
  investigationalUseDialog: {
    option: 'never',
  },
};
```

### 3. Build OHIF

```bash
# Build for production
APP_CONFIG=config/healthimaging.js yarn build

# Output will be in platform/app/dist/
```

### 4. Deploy to S3

```bash
# Get bucket name from Terraform output
OHIF_BUCKET=$(cd ../terraform && terraform output -raw ohif_viewer_bucket)

# Sync build to S3
aws s3 sync platform/app/dist/ s3://$OHIF_BUCKET/ --delete

# Invalidate CloudFront cache
DISTRIBUTION_ID=$(cd ../terraform && terraform output -raw ohif_cloudfront_distribution_id)
aws cloudfront create-invalidation --distribution-id $DISTRIBUTION_ID --paths "/*"
```

## Authentication Flow

1. User accesses OHIF Viewer URL
2. OHIF redirects to Cognito login page
3. User authenticates with Cognito
4. Cognito returns authorization code
5. OHIF exchanges code for tokens
6. OHIF uses tokens to get AWS credentials from Identity Pool
7. OHIF calls HealthImaging APIs directly with AWS credentials

## HealthImaging Integration

The OHIF HealthImaging adapter:
- Uses `GetImageSetMetadata` for study/series/instance metadata
- Uses `GetImageFrame` for pixel data retrieval
- Decodes HTJ2K frames using OpenJPH WASM codec
- Supports progressive loading for large studies

## Troubleshooting

### CORS Errors
Ensure CloudFront response headers policy allows your domain.

### Authentication Failures
1. Check Cognito callback URLs include OHIF domain
2. Verify Identity Pool role has HealthImaging permissions
3. Check browser console for token errors

### HTJ2K Decoding Issues
1. Ensure OpenJPH WASM codec is loaded
2. Check browser console for codec errors
3. Verify HealthImaging datastore has images

### Frame Loading Failures
1. Check IAM permissions for `medical-imaging:GetImageFrame`
2. Verify KMS key permissions for decryption
3. Check network tab for 403/404 errors

## Configuration Reference

| Setting | Description |
|---------|-------------|
| `datastoreID` | HealthImaging datastore ID from Terraform |
| `region` | AWS region where HealthImaging is deployed |
| `authConfig.userPoolId` | Cognito User Pool ID |
| `authConfig.userPoolWebClientId` | Cognito App Client ID |
| `authConfig.identityPoolId` | Cognito Identity Pool ID |

## Resources

- [OHIF Documentation](https://docs.ohif.org/)
- [AWS HealthImaging Documentation](https://docs.aws.amazon.com/healthimaging/)
- [OHIF HealthImaging Mode](https://docs.ohif.org/configuration/dataSources/healthimaging)
- [OpenJPH WASM](https://github.com/nicholassmith/openjph-wasm)
