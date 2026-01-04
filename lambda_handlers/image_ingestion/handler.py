import json
import boto3
import os
import uuid

ahi = boto3.client('medical-imaging')

def lambda_handler(event, context):
    """
    Triggered by S3 ObjectCreated. 
    Starts an Import Job in AWS HealthImaging.
    """
    datastore_id = os.environ.get('DATASTORE_ID')
    input_bucket = os.environ.get('INPUT_BUCKET')
    output_bucket = os.environ.get('OUTPUT_BUCKET')
    role_arn = os.environ.get('AHI_IMPORT_ROLE_ARN')
    
    for record in event['Records']:
        key = record['s3']['object']['key']
        print(f"Processing file: {key}")
        
        # Construct the URI
        s3_uri = f"s3://{input_bucket}/{key}"
        
        try:
            # Start Import Job
            job_name = f"import-{uuid.uuid4().hex[:8]}"
            response = ahi.start_dicom_import_job(
                jobName=job_name,
                datastoreId=datastore_id,
                inputS3Uri=s3_uri,
                outputS3Uri=f"s3://{output_bucket}/ahi-output/",
                dataAccessRoleArn=role_arn
            )
            print(f"Started Import Job: {response['jobId']}")
            
        except Exception as e:
            print(f"Failed to start import for {key}: {str(e)}")
            raise e
            
    return {'statusCode': 200, 'body': 'Ingestion triggered'}
