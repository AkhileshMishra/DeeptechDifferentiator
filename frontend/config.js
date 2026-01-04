// ============================================================================
// Frontend Configuration
// PLACEHOLDER - Run ./scripts/generate-frontend-config.sh after Terraform apply
// ============================================================================

window.APP_CONFIG = {
    // API Gateway endpoint - REPLACE AFTER TERRAFORM APPLY
    API_ENDPOINT: "https://YOUR_API_GATEWAY_URL.execute-api.us-east-1.amazonaws.com",
    
    // S3 bucket for uploads
    S3_BUCKET: "",
    
    // Environment
    ENVIRONMENT: "dev",
    
    // Feature flags
    ENABLE_DEBUG: true,
    
    // API routes
    ROUTES: {
        GET_IMAGE_FRAME: "/get-image-frame",
        TRIGGER_PIPELINE: "/trigger-pipeline",
        GET_PRESIGNED_URL: "/get-url"
    }
};

console.log("App Config Loaded (placeholder):", window.APP_CONFIG);
console.log("Run ./scripts/generate-frontend-config.sh after Terraform apply to auto-configure.");
