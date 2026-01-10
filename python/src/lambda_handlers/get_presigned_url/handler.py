import json
import boto3
import os
import base64
from botocore.exceptions import ClientError

s3 = boto3.client('s3')
ahi = boto3.client('medical-imaging')

def lambda_handler(event, context):
    """
    Streams image frames from AWS HealthImaging.
    Acts as a proxy since HealthImaging doesn't support browser CORS.
    
    Supports actions:
    - action=list: List all image sets in datastore
    - action=getFrame (default): Get a specific image frame
    """
    try:
        bucket = os.environ.get('BUCKET_NAME')
        datastore_id = os.environ.get('DATASTORE_ID')
        
        # Parse query parameters
        query_params = event.get('queryStringParameters', {}) or {}
        image_set_id = query_params.get('imageSetId')
        action = query_params.get('action', 'getFrame')
        
        print(f"Action: {action}, ImageSetId: {image_set_id}, Datastore: {datastore_id}")
        
        # Action: List image sets
        if action == 'list':
            return list_image_sets(datastore_id)
        
        # Action: Get frame (default)
        if not image_set_id:
            return error_response(400, 'Missing imageSetId parameter')
        
        return get_image_frame(datastore_id, image_set_id)
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return error_response(500, str(e))


def list_image_sets(datastore_id):
    """List all image sets in the datastore."""
    try:
        response = ahi.search_image_sets(
            datastoreId=datastore_id,
            searchCriteria={},
            maxResults=20
        )
        
        image_sets = response.get('imageSetsMetadataSummaries', [])
        
        return {
            'statusCode': 200,
            'headers': cors_headers(),
            'body': json.dumps({
                'source': 'healthimaging',
                'count': len(image_sets),
                'imageSets': [
                    {
                        'imageSetId': s['imageSetId'],
                        'createdAt': s.get('createdAt', '').isoformat() if hasattr(s.get('createdAt', ''), 'isoformat') else str(s.get('createdAt', '')),
                        'updatedAt': s.get('updatedAt', '').isoformat() if hasattr(s.get('updatedAt', ''), 'isoformat') else str(s.get('updatedAt', ''))
                    }
                    for s in image_sets
                ]
            })
        }
    except Exception as e:
        print(f"Error listing image sets: {str(e)}")
        return error_response(500, f"Failed to list image sets: {str(e)}")


def get_image_frame(datastore_id, image_set_id):
    """Get an image frame from HealthImaging."""
    try:
        # Step 1: Get metadata to find frame ID
        print(f"Getting metadata for image set: {image_set_id}")
        
        metadata_response = ahi.get_image_set_metadata(
            datastoreId=datastore_id,
            imageSetId=image_set_id
        )
        
        metadata_blob = metadata_response['imageSetMetadataBlob'].read()
        metadata = json.loads(metadata_blob)
        
        # Extract first frame ID
        frame_id = extract_first_frame_id(metadata)
        
        if not frame_id:
            return error_response(404, 'No frames found in image set')
        
        print(f"Found frame ID: {frame_id}")
        
        # Step 2: Get the frame data
        frame_response = ahi.get_image_frame(
            datastoreId=datastore_id,
            imageSetId=image_set_id,
            imageFrameInformation={'imageFrameId': frame_id}
        )
        
        frame_data = frame_response['imageFrameBlob'].read()
        
        print(f"Retrieved frame, size: {len(frame_data)} bytes")
        
        # Return frame as base64 (for JSON response)
        return {
            'statusCode': 200,
            'headers': cors_headers(),
            'body': json.dumps({
                'source': 'healthimaging',
                'imageSetId': image_set_id,
                'frameId': frame_id,
                'frameSize': len(frame_data),
                'data': base64.b64encode(frame_data).decode('utf-8')
            })
        }
        
    except ahi.exceptions.ResourceNotFoundException:
        return error_response(404, f'Image set not found: {image_set_id}')
    except Exception as e:
        print(f"Error getting frame: {str(e)}")
        return error_response(500, f"Failed to get frame: {str(e)}")


def extract_first_frame_id(metadata):
    """Extract the first frame ID from HealthImaging metadata."""
    try:
        study = metadata.get('Study', {})
        for series_id, series in study.get('Series', {}).items():
            for instance_id, instance in series.get('Instances', {}).items():
                frames = instance.get('ImageFrames', [])
                if frames:
                    return frames[0].get('ID')
    except Exception as e:
        print(f"Error extracting frame ID: {str(e)}")
    return None


def cors_headers():
    """Return CORS headers for browser access."""
    return {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,Authorization',
        'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
        'Content-Type': 'application/json'
    }


def error_response(status_code, message):
    """Return an error response with CORS headers."""
    return {
        'statusCode': status_code,
        'headers': cors_headers(),
        'body': json.dumps({'error': message})
    }
