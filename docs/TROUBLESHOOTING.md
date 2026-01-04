# Workshop Troubleshooting Guide

## Common Issues

### 1. Terraform Error: "Source directory does not exist"
**Cause:** You haven't run the setup script to create the dummy Lambda handlers.
**Fix:** Run `bash scripts/setup.sh` from the root directory.

### 2. Frontend says "Network Error" or 404
**Cause:** The API URL in `index.html` is incorrect or the API Gateway hasn't deployed the latest changes.
**Fix:** 1. Run `bash scripts/update_frontend.sh` to inject the correct URL.
2. Ensure you are using a CORS-enabled browser or extension for the local file, or run `python -m http.server` in the `frontend/` directory.

### 3. Pipeline Not Triggering
**Cause:** The Lambda `pipeline_trigger` might be missing permissions.
**Fix:** Check CloudWatch Logs: `/aws/lambda/pipeline-trigger-dev`.
