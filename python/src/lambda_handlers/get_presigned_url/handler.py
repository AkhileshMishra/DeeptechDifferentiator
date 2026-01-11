"""
Healthcare Imaging MLOps Platform - Get Presigned URL Lambda Handler
Generates presigned URLs for S3 DICOM file uploads.

Note: For viewing images, the frontend now uses OHIF Viewer with direct
HealthImaging access via Cognito credentials. This handler is primarily
for DICOM file uploads before ingestion into HealthImaging.
"""

import json
import os
import uuid
import boto3
from botocore.exceptions import ClientError
from botocore.config import Config

# Initialize S3 client with signature version for presigned URLs
config = Config(
    signature_version='s3v4',
    retries={'max_attempts': 3, 'mode': 'adaptive'}
)
s3_client = boto3.client('s3', config=config)


def lambda_handler(event, context):
    """
    Generates presigned URLs for S3 operations.
    
    Query Parameters:
        - operation: 'upload' or 'download' (default: 'upload')
        - filename: Original filename for upload
        - contentType: MIME type (default: application/dicom)
        - key: S3 key for download operation
    
    Returns:
        Presigned URL and metadata
    """
    print(f"Received event: {json.dumps(event)}")
    
    bucket_name = os.environ.get('BUCKET_NAME') or os.environ.get('S3_BUCKET_NAME')
    
    if not bucket_name:
        return error_response(500, "S3 bucket not configured")
    
    try:
        query_params = event.get('queryStringParameters') or {}
        operation = query_params.get('operation', 'upload')
        
        if operation == 'upload':
            return handle_upload(bucket_name, query_params)
        elif operation == 'download':
            return handle_download(bucket_name, query_params)
        else:
            return error_response(400, f"Invalid operation: {operation}")
            
    except ClientError as e:
        print(f"AWS Error: {e}")
        return error_response(500, f"AWS Error: {str(e)}")
    except Exception as e:
        print(f"Error: {e}")
        return error_response(500, f"Error: {str(e)}")


def handle_upload(bucket_name, params):
    """
    Generate presigned URL for DICOM file upload.
    
    Files are uploaded to input/ prefix which triggers the image ingestion Lambda.
    """
    filename = params.get('filename', f"{uuid.uuid4().hex}.dcm")
    content_type = params.get('contentType', 'application/dicom')
    
    # Sanitize filename
    safe_filename = "".join(c for c in filename if c.isalnum() or c in '.-_')
    if not safe_filename:
        safe_filename = f"{uuid.uuid4().hex}.dcm"
    
    # Generate unique key in input/ folder (triggers ingestion)
    upload_id = uuid.uuid4().hex[:8]
    key = f"input/{upload_id}-{safe_filename}"
    
    # Generate presigned URL for PUT
    presigned_url = s3_client.generate_presigned_url(
        'put_object',
        Params={
            'Bucket': bucket_name,
            'Key': key,
            'ContentType': content_type
        },
        ExpiresIn=3600  # 1 hour
    )
    
    return success_response({
        'url': presigned_url,
        'key': key,
        'bucket': bucket_name,
        'uploadId': upload_id,
        'expiresIn': 3600,
        'method': 'PUT',
        'headers': {
            'Content-Type': content_type
        }
    })


def handle_download(bucket_name, params):
    """
    Generate presigned URL for file download.
    """
    key = params.get('key')
    
    if not key:
        return error_response(400, "key parameter is required for download")
    
    # Verify object exists
    try:
        s3_client.head_object(Bucket=bucket_name, Key=key)
    except ClientError as e:
        if e.response['Error']['Code'] == '404':
            return error_response(404, f"File not found: {key}")
        raise
    
    # Generate presigned URL for GET
    presigned_url = s3_client.generate_presigned_url(
        'get_object',
        Params={
            'Bucket': bucket_name,
            'Key': key
        },
        ExpiresIn=3600  # 1 hour
    )
    
    return success_response({
        'url': presigned_url,
        'key': key,
        'bucket': bucket_name,
        'expiresIn': 3600,
        'method': 'GET'
    })


def success_response(data):
    """Return a successful API response."""
    return {
        'statusCode': 200,
        'headers': cors_headers(),
        'body': json.dumps(data)
    }


def error_response(status_code, message):
    """Return an error API response."""
    return {
        'statusCode': status_code,
        'headers': cors_headers(),
        'body': json.dumps({'error': message})
    }


def cors_headers():
    """Return CORS headers for API responses."""
    return {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, PUT, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-Amz-Date, X-Api-Key',
        'Content-Type': 'application/json'
    }
