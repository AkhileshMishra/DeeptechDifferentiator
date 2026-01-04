"""
Healthcare Imaging MLOps Platform - Model Evaluation Lambda Handler
Evaluates trained models and publishes metrics to CloudWatch and DynamoDB.
"""

import json
import os
import boto3
from datetime import datetime
from decimal import Decimal

# Initialize clients
s3_client = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')
cloudwatch = boto3.client('cloudwatch')
events_client = boto3.client('events')


def lambda_handler(event, context):
    """
    Triggered by EventBridge when a SageMaker Training Job completes.
    Evaluates the model and publishes metrics.
    
    Expected event structure (from SageMaker Training Job State Change):
    {
        "detail": {
            "TrainingJobName": "...",
            "TrainingJobArn": "...",
            "TrainingJobStatus": "Completed",
            "ModelArtifacts": {
                "S3ModelArtifacts": "s3://bucket/path/model.tar.gz"
            }
        }
    }
    """
    print(f"Received event: {json.dumps(event)}")
    
    # Environment variables
    model_bucket = os.environ.get('MODEL_ARTIFACTS_BUCKET', os.environ.get('MODEL_BUCKET'))
    metrics_table_name = os.environ.get('METRICS_TABLE')
    cloudwatch_namespace = os.environ.get('CLOUDWATCH_NAMESPACE', 'HealthcareImaging/ModelMetrics')
    accuracy_threshold = float(os.environ.get('ACCURACY_THRESHOLD', '0.85'))
    
    try:
        # Extract training job details from event
        detail = event.get('detail', {})
        training_job_name = detail.get('TrainingJobName', 'unknown')
        training_job_status = detail.get('TrainingJobStatus', 'Unknown')
        model_artifacts = detail.get('ModelArtifacts', {}).get('S3ModelArtifacts', '')
        
        print(f"Processing training job: {training_job_name}")
        print(f"Training job status: {training_job_status}")
        print(f"Model artifacts: {model_artifacts}")
        
        # For demo purposes, generate simulated evaluation metrics
        # In production, this would load the model and run actual evaluation
        evaluation_metrics = evaluate_model(model_artifacts)
        
        # Store metrics in DynamoDB
        if metrics_table_name:
            store_metrics_in_dynamodb(
                metrics_table_name,
                training_job_name,
                evaluation_metrics
            )
        
        # Publish metrics to CloudWatch
        publish_metrics_to_cloudwatch(
            cloudwatch_namespace,
            training_job_name,
            evaluation_metrics
        )
        
        # Check if model passes accuracy threshold
        accuracy = evaluation_metrics.get('accuracy', 0)
        
        if accuracy >= accuracy_threshold:
            print(f"Model passed evaluation with accuracy {accuracy:.4f} >= {accuracy_threshold}")
            
            # Emit ModelEvaluationPassed event to trigger model registration
            emit_evaluation_passed_event(
                training_job_name,
                model_artifacts,
                evaluation_metrics
            )
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Model evaluation passed',
                    'trainingJobName': training_job_name,
                    'accuracy': accuracy,
                    'threshold': accuracy_threshold,
                    'status': 'APPROVED'
                })
            }
        else:
            print(f"Model failed evaluation with accuracy {accuracy:.4f} < {accuracy_threshold}")
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'Model evaluation failed',
                    'trainingJobName': training_job_name,
                    'accuracy': accuracy,
                    'threshold': accuracy_threshold,
                    'status': 'REJECTED'
                })
            }
            
    except Exception as e:
        print(f"Error during model evaluation: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }


def evaluate_model(model_artifacts_path: str) -> dict:
    """
    Evaluate the trained model.
    
    In production, this would:
    1. Download model from S3
    2. Load test dataset
    3. Run inference
    4. Calculate metrics
    
    For the workshop demo, we simulate realistic metrics.
    """
    import random
    
    # Simulate evaluation metrics (in production, calculate from actual inference)
    # Using realistic values for a pneumonia detection model
    accuracy = random.uniform(0.82, 0.95)
    precision = random.uniform(0.80, 0.93)
    recall = random.uniform(0.78, 0.92)
    f1_score = 2 * (precision * recall) / (precision + recall) if (precision + recall) > 0 else 0
    auc_roc = random.uniform(0.85, 0.97)
    
    metrics = {
        'accuracy': round(accuracy, 4),
        'precision': round(precision, 4),
        'recall': round(recall, 4),
        'f1_score': round(f1_score, 4),
        'auc_roc': round(auc_roc, 4),
        'evaluation_timestamp': datetime.utcnow().isoformat(),
        'model_artifacts': model_artifacts_path
    }
    
    print(f"Evaluation metrics: {json.dumps(metrics)}")
    
    return metrics


def store_metrics_in_dynamodb(table_name: str, model_version: str, metrics: dict):
    """
    Store evaluation metrics in DynamoDB.
    """
    try:
        table = dynamodb.Table(table_name)
        
        # Convert floats to Decimal for DynamoDB
        item = {
            'model_version': model_version,
            'evaluation_timestamp': metrics['evaluation_timestamp'],
            'accuracy': Decimal(str(metrics['accuracy'])),
            'precision': Decimal(str(metrics['precision'])),
            'recall': Decimal(str(metrics['recall'])),
            'f1_score': Decimal(str(metrics['f1_score'])),
            'auc_roc': Decimal(str(metrics['auc_roc'])),
            'model_artifacts': metrics.get('model_artifacts', '')
        }
        
        table.put_item(Item=item)
        print(f"Metrics stored in DynamoDB table {table_name}")
        
    except Exception as e:
        print(f"Error storing metrics in DynamoDB: {str(e)}")
        raise


def publish_metrics_to_cloudwatch(namespace: str, model_version: str, metrics: dict):
    """
    Publish evaluation metrics to CloudWatch.
    """
    try:
        metric_data = [
            {
                'MetricName': 'ModelAccuracy',
                'Value': metrics['accuracy'],
                'Unit': 'None',
                'Dimensions': [
                    {'Name': 'ModelVersion', 'Value': model_version}
                ]
            },
            {
                'MetricName': 'ModelPrecision',
                'Value': metrics['precision'],
                'Unit': 'None',
                'Dimensions': [
                    {'Name': 'ModelVersion', 'Value': model_version}
                ]
            },
            {
                'MetricName': 'ModelRecall',
                'Value': metrics['recall'],
                'Unit': 'None',
                'Dimensions': [
                    {'Name': 'ModelVersion', 'Value': model_version}
                ]
            },
            {
                'MetricName': 'ModelF1Score',
                'Value': metrics['f1_score'],
                'Unit': 'None',
                'Dimensions': [
                    {'Name': 'ModelVersion', 'Value': model_version}
                ]
            },
            {
                'MetricName': 'ModelAUCROC',
                'Value': metrics['auc_roc'],
                'Unit': 'None',
                'Dimensions': [
                    {'Name': 'ModelVersion', 'Value': model_version}
                ]
            }
        ]
        
        cloudwatch.put_metric_data(
            Namespace=namespace,
            MetricData=metric_data
        )
        
        print(f"Metrics published to CloudWatch namespace {namespace}")
        
    except Exception as e:
        print(f"Error publishing metrics to CloudWatch: {str(e)}")
        raise


def emit_evaluation_passed_event(training_job_name: str, model_artifacts: str, metrics: dict):
    """
    Emit a custom EventBridge event when model evaluation passes.
    This triggers the model registration Lambda.
    """
    try:
        event_bus_name = os.environ.get('EVENT_BUS_NAME', 'default')
        
        event_detail = {
            'trainingJobName': training_job_name,
            'modelArtifacts': model_artifacts,
            'accuracy': metrics['accuracy'],
            'precision': metrics['precision'],
            'recall': metrics['recall'],
            'f1_score': metrics['f1_score'],
            'auc_roc': metrics['auc_roc'],
            'evaluationTimestamp': metrics['evaluation_timestamp']
        }
        
        response = events_client.put_events(
            Entries=[
                {
                    'Source': 'imaging.mlops',
                    'DetailType': 'ModelEvaluationPassed',
                    'Detail': json.dumps(event_detail),
                    'EventBusName': event_bus_name
                }
            ]
        )
        
        print(f"Emitted ModelEvaluationPassed event: {response}")
        
    except Exception as e:
        print(f"Error emitting event: {str(e)}")
        raise
