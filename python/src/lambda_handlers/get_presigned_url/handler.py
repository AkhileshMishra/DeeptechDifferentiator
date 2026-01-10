import json
import boto3
import os
import base64
import gzip
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
    """Get an image frame from HealthImaging and convert to browser-displayable format."""
    try:
        # Step 1: Get metadata to find frame ID and image dimensions
        print(f"Getting metadata for image set: {image_set_id}")
        
        metadata_response = ahi.get_image_set_metadata(
            datastoreId=datastore_id,
            imageSetId=image_set_id
        )
        
        # Metadata is gzip compressed
        metadata_blob = metadata_response['imageSetMetadataBlob'].read()
        
        # Decompress if gzipped (starts with 0x1f 0x8b)
        if metadata_blob[:2] == b'\x1f\x8b':
            metadata_blob = gzip.decompress(metadata_blob)
        
        metadata = json.loads(metadata_blob.decode('utf-8'))
        
        # Extract first frame ID and image info
        frame_info = extract_frame_info(metadata)
        
        if not frame_info:
            return error_response(404, 'No frames found in image set')
        
        frame_id = frame_info['frameId']
        width = frame_info.get('width', 512)
        height = frame_info.get('height', 512)
        bits_allocated = frame_info.get('bitsAllocated', 8)
        photometric = frame_info.get('photometric', 'MONOCHROME2')
        
        print(f"Found frame ID: {frame_id}, dimensions: {width}x{height}, bits: {bits_allocated}, photometric: {photometric}")
        
        # Step 2: Get the frame data
        frame_response = ahi.get_image_frame(
            datastoreId=datastore_id,
            imageSetId=image_set_id,
            imageFrameInformation={'imageFrameId': frame_id}
        )
        
        frame_data = frame_response['imageFrameBlob'].read()
        original_size = len(frame_data)
        
        print(f"Retrieved frame, size: {original_size} bytes, first bytes: {frame_data[:8].hex()}")
        
        # Detect format and convert if needed
        output_format = 'original'
        
        # Check if it's already JPEG (browser can display directly)
        if frame_data[:2] == b'\xff\xd8':
            output_format = 'jpeg'
            print("Frame is JPEG - returning as-is")
        # Check if it's PNG
        elif frame_data[:4] == b'\x89PNG':
            output_format = 'png'
            print("Frame is PNG - returning as-is")
        # JP2 or J2K - try to convert using Pillow
        elif frame_data[:2] == b'\xff\x4f' or (len(frame_data) > 5 and frame_data[4:6] == b'jP'):
            output_format = 'jp2'
            print("Frame is JP2/J2K - attempting conversion")
            
            # Try to decode using Pillow (requires openjpeg library)
            try:
                from PIL import Image
                import io
                
                # Load JP2 image
                img = Image.open(io.BytesIO(frame_data))
                
                # Convert to PNG
                png_buffer = io.BytesIO()
                img.save(png_buffer, format='PNG')
                frame_data = png_buffer.getvalue()
                output_format = 'png'
                print(f"Converted to PNG using Pillow: {len(frame_data)} bytes")
            except Exception as e:
                print(f"Pillow JP2 decode failed: {e}")
                # Return raw JP2 - frontend will handle
        
        # Return frame as base64 with metadata
        return {
            'statusCode': 200,
            'headers': cors_headers(),
            'body': json.dumps({
                'source': 'healthimaging',
                'imageSetId': image_set_id,
                'frameId': frame_id,
                'frameSize': original_size,
                'outputSize': len(frame_data),
                'width': width,
                'height': height,
                'format': output_format,
                'bitsAllocated': bits_allocated,
                'photometric': photometric,
                'data': base64.b64encode(frame_data).decode('utf-8')
            })
        }
        
    except ahi.exceptions.ResourceNotFoundException:
        return error_response(404, f'Image set not found: {image_set_id}')
    except Exception as e:
        print(f"Error getting frame: {str(e)}")
        return error_response(500, f"Failed to get frame: {str(e)}")


def extract_frame_info(metadata):
    """Extract the first frame ID and image dimensions from HealthImaging metadata."""
    try:
        study = metadata.get('Study', {})
        for series_id, series in study.get('Series', {}).items():
            for instance_id, instance in series.get('Instances', {}).items():
                frames = instance.get('ImageFrames', [])
                if frames:
                    # Get DICOM attributes for dimensions
                    dicom_tags = instance.get('DICOM', {})
                    width = dicom_tags.get('Columns', 512)
                    height = dicom_tags.get('Rows', 512)
                    bits_allocated = dicom_tags.get('BitsAllocated', 8)
                    photometric = dicom_tags.get('PhotometricInterpretation', 'MONOCHROME2')
                    
                    return {
                        'frameId': frames[0].get('ID'),
                        'width': width,
                        'height': height,
                        'bitsAllocated': bits_allocated,
                        'photometric': photometric
                    }
    except Exception as e:
        print(f"Error extracting frame info: {str(e)}")
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
