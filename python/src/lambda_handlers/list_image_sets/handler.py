"""
Healthcare Imaging MLOps Platform - List Image Sets Lambda Handler
Lists all image sets in the HealthImaging datastore.
"""

import json
import os
import boto3
from botocore.config import Config
from datetime import datetime, timedelta, timezone

# Initialize client with retry configuration
config = Config(
    retries={'max_attempts': 3, 'mode': 'adaptive'},
    connect_timeout=10,
    read_timeout=30
)

ahi_client = boto3.client('medical-imaging', config=config)


def lambda_handler(event, context):
    """
    Lists image sets from AWS HealthImaging datastore.
    
    Query Parameters:
        - maxResults: Maximum number of results (default: 50)
        - nextToken: Pagination token
    
    Returns:
        List of image sets with metadata
    """
    print(f"Received event: {json.dumps(event)}")
    
    datastore_id = os.environ.get('DATASTORE_ID')
    
    if not datastore_id:
        return error_response(500, "DATASTORE_ID not configured")
    
    print(f"Using datastore_id: {datastore_id}")
    
    try:
        # Parse query parameters
        query_params = event.get('queryStringParameters') or {}
        max_results = int(query_params.get('maxResults', '50'))
        next_token = query_params.get('nextToken')
        
        # Build search request
        # Use createdAt BETWEEN filter to get all image sets
        now = datetime.now(timezone.utc)
        past = datetime(2020, 1, 1, tzinfo=timezone.utc)
        future = now + timedelta(days=1)
        
        search_params = {
            'datastoreId': datastore_id,
            'maxResults': min(max_results, 100),
            'searchCriteria': {
                'filters': [
                    {
                        'values': [
                            {'createdAt': past},
                            {'createdAt': future}
                        ],
                        'operator': 'BETWEEN'
                    }
                ]
            }
        }
        
        if next_token:
            search_params['nextToken'] = next_token
        
        print(f"Calling searchImageSets...")
        
        response = ahi_client.search_image_sets(**search_params)
        
        print(f"Got {len(response.get('imageSetsMetadataSummaries', []))} image sets")
        
        # Format response
        image_sets = []
        for item in response.get('imageSetsMetadataSummaries', []):
            image_set = {
                'imageSetId': item.get('imageSetId'),
                'version': item.get('version'),
                'createdAt': item.get('createdAt').isoformat() if item.get('createdAt') else None,
                'updatedAt': item.get('updatedAt').isoformat() if item.get('updatedAt') else None,
                'imageSetState': item.get('imageSetState'),
                'imageSetWorkflowStatus': item.get('imageSetWorkflowStatus'),
                # DICOM metadata if available
                'DICOMTags': item.get('DICOMTags', {})
            }
            image_sets.append(image_set)
        
        result = {
            'imageSets': image_sets,
            'datastoreId': datastore_id,
            'count': len(image_sets)
        }
        
        # Include pagination token if present
        if response.get('nextToken'):
            result['nextToken'] = response['nextToken']
        
        return success_response(result)
        
    except ahi_client.exceptions.ResourceNotFoundException as e:
        print(f"Datastore not found: {str(e)}")
        return error_response(404, f"Datastore not found: {datastore_id}")
        
    except ahi_client.exceptions.AccessDeniedException as e:
        print(f"Access denied: {str(e)}")
        return error_response(403, "Access denied to HealthImaging datastore")
        
    except Exception as e:
        error_msg = str(e)
        print(f"Error listing image sets: {error_msg}")
        import traceback
        traceback.print_exc()
        
        # Return empty list if no image sets found (not an error)
        if 'ValidationException' in error_msg or 'no image sets' in error_msg.lower():
            return success_response({
                'imageSets': [],
                'datastoreId': datastore_id,
                'count': 0
            })
        
        return error_response(500, f"Error listing image sets: {error_msg}")


def success_response(data):
    """Return a successful API response."""
    return {
        'statusCode': 200,
        'headers': cors_headers(),
        'body': json.dumps(data, default=str)
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
        'Access-Control-Allow-Methods': 'GET, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
        'Content-Type': 'application/json'
    }
