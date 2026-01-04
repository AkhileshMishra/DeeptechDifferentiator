#!/bin/bash
set -e

echo "Fetching API Endpoint from Terraform..."
cd terraform
API_URL=$(terraform output -raw api_endpoint)
cd ..

if [ -z "$API_URL" ]; then
    echo "Error: Could not find api_endpoint in Terraform outputs."
    exit 1
fi

echo "Found API URL: $API_URL"

# Replace the placeholder in index.html
# Works on both MacOS (sed -i '') and Linux (sed -i)
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s|https://YOUR_API_GATEWAY_URL.execute-api.us-east-1.amazonaws.com/prod|$API_URL|g" frontend/index.html
else
    sed -i "s|https://YOUR_API_GATEWAY_URL.execute-api.us-east-1.amazonaws.com/prod|$API_URL|g" frontend/index.html
fi

echo "✅ frontend/index.html updated successfully!"
