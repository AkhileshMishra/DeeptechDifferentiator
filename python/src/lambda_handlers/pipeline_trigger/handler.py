import json
import boto3
import os
import time

sm_client = boto3.client('sagemaker')

def lambda_handler(event, context):
    print(f"Received Event: {json.dumps(event)}")
    
    # Get pipeline ARN from environment (set by Terraform)
    pipeline_arn = os.environ.get('SAGEMAKER_PIPELINE_ARN')
    
    # Extract pipeline name from ARN
    # ARN format: arn:aws:sagemaker:region:account:pipeline/pipeline-name
    if pipeline_arn:
        pipeline_name = pipeline_arn.split('/')[-1]
    else:
        pipeline_name = os.environ.get('PIPELINE_NAME', 'HealthcareImagingPipeline')
    
    print(f"Using pipeline: {pipeline_name}")
    
    try:
        # Parse body from API Gateway
        body = {}
        if 'body' in event:
            body = json.loads(event['body']) if event['body'] else {}
        
        image_set_id = body.get('imageSetId', 'demo-image')
        
        # Start SageMaker Pipeline
        response = sm_client.start_pipeline_execution(
            PipelineName=pipeline_name,
            PipelineExecutionDisplayName=f"Verification-{image_set_id[:20]}-{int(time.time())}"
        )
        
        print(f"Pipeline started: {response['PipelineExecutionArn']}")
        
        return {
            'statusCode': 200,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Content-Type': 'application/json'
            },
            'body': json.dumps({
                'message': 'Pipeline execution started',
                'executionArn': response['PipelineExecutionArn']
            })
        }
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Content-Type': 'application/json'
            },
            'body': json.dumps({'error': str(e)})
        }
