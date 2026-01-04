import json
import boto3
import os

s3 = boto3.client('s3')

def lambda_handler(event, context):
    try:
        bucket = os.environ.get('BUCKET_NAME')
        image_set_id = event.get('queryStringParameters', {}).get('imageSetId', 'test-image')
        
        # For the workshop, we serve the S3 object URL
        # In a real scenario, this would call HealthImaging.GetImageFrame
        key = f"upload/{image_set_id}.dcm"
        
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
            'body': json.dumps({'url': url})
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
