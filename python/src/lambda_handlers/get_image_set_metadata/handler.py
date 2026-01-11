"""
Healthcare Imaging MLOps Platform - Get Image Set Metadata Lambda Handler
Retrieves detailed metadata for a specific image set including DICOM tags.
"""

import json
import os
import boto3
from botocore.config import Config

# Initialize client with retry configuration
config = Config(
    retries={'max_attempts': 3, 'mode': 'adaptive'},
    connect_timeout=10,
    read_timeout=30
)

ahi_client = boto3.client('medical-imaging', config=config)


def lambda_handler(event, context):
    """
    Gets detailed metadata for an image set from AWS HealthImaging.
    
    Query Parameters:
        - imageSetId: (required) The image set ID
        - versionId: (optional) Specific version of the image set
    
    Returns:
        Detailed image set metadata including DICOM tags, study/series info
    """
    print(f"Received event: {json.dumps(event)}")
    
    datastore_id = os.environ.get('DATASTORE_ID')
    
    if not datastore_id:
        return error_response(500, "DATASTORE_ID not configured")
    
    try:
        # Parse query parameters
        query_params = event.get('queryStringParameters') or {}
        image_set_id = query_params.get('imageSetId')
        version_id = query_params.get('versionId')
        
        if not image_set_id:
            return error_response(400, "imageSetId is required")
        
        # Get image set metadata
        get_params = {
            'datastoreId': datastore_id,
            'imageSetId': image_set_id
        }
        
        if version_id:
            get_params['versionId'] = version_id
        
        # Get basic image set info
        image_set_response = ahi_client.get_image_set(**get_params)
        
        # Get detailed metadata (DICOM tags)
        metadata_response = ahi_client.get_image_set_metadata(**get_params)
        
        # Parse the metadata blob - it may be gzip compressed
        metadata_blob = metadata_response.get('imageSetMetadataBlob')
        if metadata_blob:
            # The blob is returned as a streaming body, read it
            metadata_content = metadata_blob.read()
            
            # Check if it's gzip compressed (starts with 0x1f 0x8b)
            if metadata_content[:2] == b'\x1f\x8b':
                import gzip
                metadata_content = gzip.decompress(metadata_content)
            
            try:
                dicom_metadata = json.loads(metadata_content)
            except json.JSONDecodeError as e:
                print(f"JSON decode error: {e}")
                print(f"Content preview: {metadata_content[:500]}")
                dicom_metadata = {'raw': metadata_content.decode('utf-8', errors='ignore')[:1000]}
        else:
            dicom_metadata = {}
        
        # Extract key DICOM information for viewer
        study_info = extract_study_info(dicom_metadata)
        
        result = {
            'imageSetId': image_set_id,
            'datastoreId': datastore_id,
            'versionId': image_set_response.get('versionId'),
            'imageSetState': image_set_response.get('imageSetState'),
            'imageSetWorkflowStatus': image_set_response.get('imageSetWorkflowStatus'),
            'createdAt': image_set_response.get('createdAt'),
            'updatedAt': image_set_response.get('updatedAt'),
            
            # Study-level information for OHIF
            'study': study_info,
            
            # Full DICOM metadata
            'dicomMetadata': dicom_metadata,
            
            # Content type from response
            'contentType': metadata_response.get('contentType', 'application/json')
        }
        
        return success_response(result)
        
    except ahi_client.exceptions.ResourceNotFoundException as e:
        print(f"Image set not found: {str(e)}")
        return error_response(404, f"Image set not found: {image_set_id}")
        
    except ahi_client.exceptions.AccessDeniedException as e:
        print(f"Access denied: {str(e)}")
        return error_response(403, "Access denied to image set")
        
    except Exception as e:
        import traceback
        print(f"Error getting image set metadata: {str(e)}")
        print(f"Traceback: {traceback.format_exc()}")
        return error_response(500, f"Error getting metadata: {str(e)}")


def extract_study_info(dicom_metadata):
    """
    Extract study-level information from DICOM metadata for OHIF viewer.
    
    Args:
        dicom_metadata: Parsed DICOM metadata from HealthImaging
        
    Returns:
        Dictionary with study information
    """
    study_info = {
        'StudyInstanceUID': None,
        'StudyDate': None,
        'StudyTime': None,
        'StudyDescription': None,
        'PatientName': None,
        'PatientID': None,
        'Modality': None,
        'SeriesCount': 0,
        'InstanceCount': 0,
        'series': []
    }
    
    try:
        # Get patient info from top-level Patient key
        if 'Patient' in dicom_metadata:
            patient = dicom_metadata['Patient']
            patient_dicom = patient.get('DICOM', {})
            study_info['PatientName'] = patient_dicom.get('PatientName')
            study_info['PatientID'] = patient_dicom.get('PatientID')
        
        # Get study info from top-level Study key (HealthImaging schema 1.1)
        if 'Study' in dicom_metadata:
            study_data = dicom_metadata['Study']
            study_dicom = study_data.get('DICOM', {})
            
            study_info['StudyInstanceUID'] = study_dicom.get('StudyInstanceUID')
            study_info['StudyDate'] = study_dicom.get('StudyDate')
            study_info['StudyTime'] = study_dicom.get('StudyTime')
            study_info['StudyDescription'] = study_dicom.get('StudyDescription')
            
            # Get series from Study.Series
            series_dict = study_data.get('Series', {})
            study_info['SeriesCount'] = len(series_dict)
            
            for series_uid, series_data in series_dict.items():
                series_dicom = series_data.get('DICOM', {})
                instances = series_data.get('Instances', {})
                
                series_info = {
                    'SeriesInstanceUID': series_uid,
                    'SeriesNumber': series_dicom.get('SeriesNumber'),
                    'SeriesDescription': series_dicom.get('SeriesDescription'),
                    'Modality': series_dicom.get('Modality'),
                    'InstanceCount': len(instances),
                    'instances': []
                }
                
                # Set modality at study level
                if not study_info['Modality']:
                    study_info['Modality'] = series_dicom.get('Modality')
                
                # Get instance info
                for instance_uid, instance_data in instances.items():
                    instance_dicom = instance_data.get('DICOM', {})
                    image_frames = instance_data.get('ImageFrames', [])
                    
                    instance_info = {
                        'SOPInstanceUID': instance_uid,
                        'InstanceNumber': instance_dicom.get('InstanceNumber'),
                        'Rows': instance_dicom.get('Rows'),
                        'Columns': instance_dicom.get('Columns'),
                        'BitsAllocated': instance_dicom.get('BitsAllocated'),
                        'PhotometricInterpretation': instance_dicom.get('PhotometricInterpretation'),
                        'FrameCount': len(image_frames),
                        'ImageFrames': image_frames
                    }
                    series_info['instances'].append(instance_info)
                    study_info['InstanceCount'] += 1
                
                study_info['series'].append(series_info)
                
    except Exception as e:
        print(f"Error extracting study info: {str(e)}")
        import traceback
        print(traceback.format_exc())
    
    return study_info


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
