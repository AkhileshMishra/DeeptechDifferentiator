import json
import boto3
import os
from botocore.exceptions import ClientError

s3 = boto3.client('s3')
ahi = boto3.client('medical-imaging')

def lambda_handler(event, context):
    """
    Returns image frame URL - tries HealthImaging first, falls back to S3.
    """
    try:
        bucket = os.environ.get('BUCKET_NAME')
        datastore_id = os.environ.get('DATASTORE_ID')
        image_set_id = event.get('queryStringParameters', {}).get('imageSetId', 'test-image')
        
        print(f"Looking for imageSetId: {image_set_id}, datastore: {datastore_id}")
        
        # Try HealthImaging first if datastore is configured
        if datastore_id:
            try:
                # List all image sets and find one (for demo purposes)
                # In production, you'd search by specific DICOM tags
                response = ahi.search_image_sets(
                    datastoreId=datastore_id,
                    searchCriteria={},
                    maxResults=10
                )
                
                image_sets = response.get('imageSetsMetadataSummaries', [])
                print(f"Found {len(image_sets)} image sets in HealthImaging")
                
                if image_sets:
                    # Use the first available image set
                    ahi_image_set_id = image_sets[0]['imageSetId']
                    print(f"Using HealthImaging image set: {ahi_image_set_id}")
                    
                    # Get metadata to find frame IDs
                    metadata_response = ahi.get_image_set_metadata(
                        datastoreId=datastore_id,
                        imageSetId=ahi_image_set_id
                    )
                    
                    metadata = json.loads(metadata_response['imageSetMetadataBlob'].read())
                    print(f"Got metadata for image set")
                    
                    # Extract first frame ID from metadata
                    frame_id = extract_first_frame_id(metadata)
                    print(f"Extracted frame ID: {frame_id}")
                    
                    if frame_id:
                        # Get the image frame directly and return as base64
                        frame_response = ahi.get_image_frame(
                            datastoreId=datastore_id,
                            imageSetId=ahi_image_set_id,
                            imageFrameInformation={'imageFrameId': frame_id}
                        )
                        
                        frame_data = frame_response['imageFrameBlob'].read()
                        import base64
                        
                        print(f"Successfully retrieved frame from HealthImaging, size: {len(frame_data)} bytes")
                        
                        return {
                            'statusCode': 200,
                            'headers': {
                                'Access-Control-Allow-Origin': '*',
                                'Access-Control-Allow-Headers': '*',
                                'Content-Type': 'application/json'
                            },
                            'body': json.dumps({
                                'source': 'healthimaging',
                                'imageSetId': ahi_image_set_id,
                                'frameId': frame_id,
                                'data': base64.b64encode(frame_data).decode('utf-8')
                            })
                        }
            except Exception as ahi_error:
                print(f"HealthImaging lookup failed: {str(ahi_error)}")
        
        # Fallback to S3 presigned URL
        print("Falling back to S3")
        possible_keys = [
            f"input/{image_set_id}.dcm",
            f"input/{image_set_id}.DCM",
            f"upload/{image_set_id}.dcm",
            f"upload/{image_set_id}.DCM",
        ]
        
        key = None
        for possible_key in possible_keys:
            try:
                s3.head_object(Bucket=bucket, Key=possible_key)
                key = possible_key
                break
            except ClientError:
                continue
        
        if not key:
            return {
                'statusCode': 404,
                'headers': {
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Headers': '*'
                },
                'body': json.dumps({'error': f'File not found for imageSetId: {image_set_id}'})
            }
        
        url = s3.generate_presigned_url(
            'get_object',
            Params={'Bucket': bucket, 'Key': key},
            ExpiresIn=3600
        )
        
        return {
            'statusCode': 200,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': '*'
            },
            'body': json.dumps({
                'source': 's3',
                'url': url
            })
        }
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }


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
