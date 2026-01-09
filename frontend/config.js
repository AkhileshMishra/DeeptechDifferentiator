// ============================================================================
// Frontend Configuration
// PLACEHOLDER - Run ./scripts/generate-frontend-config.sh after Terraform apply
// ============================================================================

window.APP_CONFIG = {
    // API Gateway endpoint
    API_ENDPOINT: "https://v0437mg6s5.execute-api.us-east-1.amazonaws.com",
    
    // S3 bucket for uploads
    S3_BUCKET: "healthcare-imaging-dev-training-data-637423443220",
    
    // HealthImaging Datastore ID
    DATASTORE_ID: "2c5ad42eef2b4f82a7fe3e8905006d68",
    
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

console.log("App Config Loaded:", window.APP_CONFIG);
