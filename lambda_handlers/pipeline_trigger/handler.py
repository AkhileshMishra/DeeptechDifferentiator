import json
import boto3
import os
import time

sm_client = boto3.client('sagemaker')

def lambda_handler(event, context):
    """
    Triggered by API Gateway (Manual Verify) or EventBridge (Auto Verify).
    Starts the SageMaker Pipeline.
    """
    print(f"Received Event: {json.dumps(event)}")
    
    # Get pipeline name from ARN or use default
    pipeline_arn = os.environ.get('SAGEMAKER_PIPELINE_ARN', '')
    # Extract pipeline name from ARN: arn:aws:sagemaker:region:account:pipeline/name
    if pipeline_arn:
        pipeline_name = pipeline_arn.split('/')[-1]
    else:
        pipeline_name = os.environ.get('PIPELINE_NAME', 'DeepTechPipeline')
    
    s3_bucket = os.environ.get('S3_BUCKET') or os.environ.get('TRAINING_DATA_BUCKET', '')
    
    try:
        # 1. Parse Input
        # Handle both API Gateway events (body) and EventBridge events (detail)
        if 'body' in event:
            body = json.loads(event['body'])
            image_set_id = body.get('imageSetId')
        else:
            image_set_id = event.get('detail', {}).get('imageSetId', 'unknown-image')

        # 2. Define Pipeline Parameters
        # We pass the new image location to the pipeline to "retrain"
        # Note: Parameter name must match SageMaker pipeline definition (InputDataUri)
        execution_params = [
            {
                'Name': 'InputDataUri',
                'Value': f"s3://{s3_bucket}/input/{image_set_id}"
            }
        ]

        # 3. Start Execution
        response = sm_client.start_pipeline_execution(
            PipelineName=pipeline_name,
            PipelineExecutionDisplayName=f"Retrain-{image_set_id}-{int(time.time())}",
            PipelineParameters=execution_params
        )
        
        print(f"Pipeline started: {response['PipelineExecutionArn']}")

        return {
            'statusCode': 200,
            'headers': {'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({
                'message': 'Pipeline execution started successfully',
                'executionArn': response['PipelineExecutionArn']
            })
        }

    except Exception as e:
        print(f"Error starting pipeline: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
