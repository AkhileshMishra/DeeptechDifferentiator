"""
Healthcare Imaging MLOps Platform - Image Ingestion Lambda Handler
Processes uploaded DICOM images and ingests them into AWS HealthImaging.
"""

import json
import os
import uuid
import boto3
from datetime import datetime

# Initialize clients
s3_client = boto3.client('s3')
ahi_client = boto3.client('medical-imaging')
dynamodb = boto3.resource('dynamodb')
events_client = boto3.client('events')


def lambda_handler(event, context):
    """
    Triggered by S3 ObjectCreated event when a DICOM file is uploaded.
    Starts an Import Job in AWS HealthImaging.
    
    HealthImaging requires inputS3Uri to be a folder, not a single file.
    We copy the file to a unique import folder, then start the import.
    """
    print(f"Received event: {json.dumps(event)}")
    
    # Environment variables
    datastore_id = os.environ.get('DATASTORE_ID', os.environ.get('HEALTHIMAGING_DATASTORE_ID'))
    input_bucket = os.environ.get('INPUT_BUCKET', os.environ.get('TRAINING_BUCKET'))
    output_bucket = os.environ.get('OUTPUT_BUCKET', input_bucket)
    role_arn = os.environ.get('AHI_IMPORT_ROLE_ARN', os.environ.get('DATA_ACCESS_ROLE_ARN'))
    tracking_table = os.environ.get('IMAGE_TRACKING_TABLE')
    event_bus_name = os.environ.get('EVENT_BUS_NAME', 'default')
    
    results = []
    
    for record in event.get('Records', []):
        try:
            # Extract S3 information
            bucket = record['s3']['bucket']['name']
            key = record['s3']['object']['key']
            
            print(f"Processing file: s3://{bucket}/{key}")
            
            # Skip non-DICOM files
            if not key.lower().endswith(('.dcm', '.dicom')):
                print(f"Skipping non-DICOM file: {key}")
                continue
            
            # Generate unique job name and folder
            job_name = f"import-{uuid.uuid4().hex[:8]}"
            import_folder = f"ahi-import/{job_name}/"
            
            # Get the filename from the key
            filename = key.split('/')[-1]
            
            # Copy file to import folder (HealthImaging needs a folder, not a single file)
            copy_source = {'Bucket': bucket, 'Key': key}
            new_key = f"{import_folder}{filename}"
            
            print(f"Copying {key} to {new_key}")
            s3_client.copy_object(
                CopySource=copy_source,
                Bucket=bucket,
                Key=new_key
            )
            
            # Construct S3 URIs - inputS3Uri must be a folder
            input_s3_uri = f"s3://{bucket}/{import_folder}"
            output_s3_uri = f"s3://{output_bucket}/ahi-output/{job_name}/"
            
            print(f"Starting import job with inputS3Uri: {input_s3_uri}")
            
            # Start DICOM Import Job
            response = ahi_client.start_dicom_import_job(
                jobName=job_name,
                datastoreId=datastore_id,
                inputS3Uri=input_s3_uri,
                outputS3Uri=output_s3_uri,
                dataAccessRoleArn=role_arn
            )
            
            job_id = response['jobId']
            print(f"Started Import Job: {job_id}")
            
            # Track the ingestion in DynamoDB
            if tracking_table:
                track_ingestion(
                    tracking_table,
                    job_id=job_id,
                    source_key=key,
                    datastore_id=datastore_id
                )
            
            # Emit ingestion started event
            emit_ingestion_event(
                event_bus_name=event_bus_name,
                job_id=job_id,
                source_key=key,
                datastore_id=datastore_id
            )
            
            results.append({
                'key': key,
                'jobId': job_id,
                'status': 'STARTED'
            })
            
        except Exception as e:
            print(f"Error processing {record}: {str(e)}")
            results.append({
                'key': record.get('s3', {}).get('object', {}).get('key', 'unknown'),
                'error': str(e),
                'status': 'FAILED'
            })
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Ingestion processing complete',
            'results': results
        })
    }


def track_ingestion(table_name: str, job_id: str, source_key: str, datastore_id: str):
    """
    Track the ingestion job in DynamoDB.
    """
    try:
        table = dynamodb.Table(table_name)
        
        item = {
            'image_id': job_id,
            'ingestion_timestamp': datetime.utcnow().isoformat(),
            'source_key': source_key,
            'datastore_id': datastore_id,
            'status': 'INGESTING',
            'verification_status': 'PENDING'
        }
        
        table.put_item(Item=item)
        print(f"Tracked ingestion in DynamoDB: {job_id}")
        
    except Exception as e:
        print(f"Error tracking ingestion: {str(e)}")
        # Don't raise - ingestion was successful


def emit_ingestion_event(event_bus_name: str, job_id: str, source_key: str, datastore_id: str):
    """
    Emit a custom EventBridge event for the ingestion.
    """
    try:
        event_detail = {
            'jobId': job_id,
            'sourceKey': source_key,
            'datastoreId': datastore_id,
            'timestamp': datetime.utcnow().isoformat(),
            'status': 'INGESTION_STARTED'
        }
        
        response = events_client.put_events(
            Entries=[
                {
                    'Source': 'imaging.mlops',
                    'DetailType': 'DICOMIngestionStarted',
                    'Detail': json.dumps(event_detail),
                    'EventBusName': event_bus_name
                }
            ]
        )
        
        print(f"Emitted DICOMIngestionStarted event: {response}")
        
    except Exception as e:
        print(f"Error emitting event: {str(e)}")
        # Don't raise - ingestion was successful
