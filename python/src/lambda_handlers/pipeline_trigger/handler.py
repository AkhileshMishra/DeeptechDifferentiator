import json
import boto3
import os
import time

sm_client = boto3.client('sagemaker')

def lambda_handler(event, context):
    print(f"Received Event: {json.dumps(event)}")
    
    # Defaults
    pipeline_name = os.environ.get('PIPELINE_NAME', 'HealthcareImagingPipeline')
    bucket_name = os.environ.get('S3_BUCKET')
    
    try:
        # Parse body from API Gateway
        body = {}
        if 'body' in event:
            body = json.loads(event['body'])
        
        image_set_id = body.get('imageSetId', 'demo-image')
        
        # Start SageMaker Pipeline
        response = sm_client.start_pipeline_execution(
            PipelineName=pipeline_name,
            PipelineExecutionDisplayName=f"Verification-{image_set_id}-{int(time.time())}",
            PipelineParameters=[
                {'Name': 'InputDataUrl', 'Value': f"s3://{bucket_name}/upload/{image_set_id}.dcm"}
            ]
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Pipeline execution started',
                'executionArn': response['PipelineExecutionArn']
            })
        }
    except Exception as e:
        print(e)
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
