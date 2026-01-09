import json
import boto3
import os
from botocore.exceptions import ClientError

s3 = boto3.client('s3')

def lambda_handler(event, context):
    try:
        bucket = os.environ.get('BUCKET_NAME')
        image_set_id = event.get('queryStringParameters', {}).get('imageSetId', 'test-image')
        
        # Try multiple file paths and extensions (case-insensitive handling)
        possible_keys = [
            f"input/{image_set_id}.dcm",
            f"input/{image_set_id}.DCM",
            f"upload/{image_set_id}.dcm",
            f"upload/{image_set_id}.DCM",
        ]
        
        # Find the file that exists
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
            'body': json.dumps({'url': url})
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
