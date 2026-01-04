"""
Healthcare Imaging MLOps Platform - Model Registry Lambda Handler
Registers approved models in SageMaker Model Registry.
"""

import json
import os
import boto3
from datetime import datetime

# Initialize clients
sagemaker_client = boto3.client('sagemaker')
events_client = boto3.client('events')


def lambda_handler(event, context):
    """
    Triggered by EventBridge when model evaluation passes.
    Registers the model in SageMaker Model Registry.
    
    Expected event structure (from ModelEvaluationPassed event):
    {
        "detail": {
            "trainingJobName": "...",
            "modelArtifacts": "s3://bucket/path/model.tar.gz",
            "accuracy": 0.92,
            "precision": 0.90,
            "recall": 0.88,
            "f1_score": 0.89,
            "auc_roc": 0.95,
            "evaluationTimestamp": "..."
        }
    }
    """
    print(f"Received event: {json.dumps(event)}")
    
    # Environment variables
    model_package_group = os.environ.get('MODEL_PACKAGE_GROUP', 'healthcare-imaging-models')
    sagemaker_role_arn = os.environ.get('SAGEMAKER_ROLE_ARN')
    inference_image_uri = os.environ.get('INFERENCE_IMAGE_URI', '')
    
    try:
        # Extract details from event
        detail = event.get('detail', {})
        training_job_name = detail.get('trainingJobName', 'unknown')
        model_artifacts = detail.get('modelArtifacts', '')
        accuracy = detail.get('accuracy', 0)
        precision = detail.get('precision', 0)
        recall = detail.get('recall', 0)
        f1_score = detail.get('f1_score', 0)
        auc_roc = detail.get('auc_roc', 0)
        
        print(f"Registering model from training job: {training_job_name}")
        print(f"Model artifacts: {model_artifacts}")
        
        # Ensure model package group exists
        ensure_model_package_group_exists(model_package_group)
        
        # Get inference image URI if not provided
        if not inference_image_uri:
            inference_image_uri = get_default_inference_image()
        
        # Create model package (register model)
        model_package_arn = create_model_package(
            model_package_group=model_package_group,
            model_artifacts=model_artifacts,
            inference_image_uri=inference_image_uri,
            training_job_name=training_job_name,
            metrics={
                'accuracy': accuracy,
                'precision': precision,
                'recall': recall,
                'f1_score': f1_score,
                'auc_roc': auc_roc
            }
        )
        
        print(f"Model registered successfully: {model_package_arn}")
        
        # Emit model registered event
        emit_model_registered_event(
            model_package_arn=model_package_arn,
            training_job_name=training_job_name,
            accuracy=accuracy
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Model registered successfully',
                'modelPackageArn': model_package_arn,
                'trainingJobName': training_job_name,
                'accuracy': accuracy
            })
        }
        
    except Exception as e:
        print(f"Error registering model: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }


def ensure_model_package_group_exists(group_name: str):
    """
    Ensure the model package group exists, create if not.
    """
    try:
        sagemaker_client.describe_model_package_group(
            ModelPackageGroupName=group_name
        )
        print(f"Model package group {group_name} exists")
    except sagemaker_client.exceptions.ClientError as e:
        if 'does not exist' in str(e) or 'ResourceNotFound' in str(e):
            print(f"Creating model package group: {group_name}")
            sagemaker_client.create_model_package_group(
                ModelPackageGroupName=group_name,
                ModelPackageGroupDescription='Healthcare Imaging MLOps - Pneumonia Detection Models'
            )
            print(f"Model package group {group_name} created")
        else:
            raise


def get_default_inference_image() -> str:
    """
    Get the default inference container image URI.
    Uses the TensorFlow Serving container from AWS.
    """
    region = os.environ.get('AWS_REGION', 'us-east-1')
    account_id = os.environ.get('AWS_ACCOUNT_ID', '')
    
    # Use AWS Deep Learning Container for TensorFlow inference
    # Format: {account}.dkr.ecr.{region}.amazonaws.com/tensorflow-inference:2.13-cpu
    dlc_account_map = {
        'us-east-1': '763104351884',
        'us-east-2': '763104351884',
        'us-west-1': '763104351884',
        'us-west-2': '763104351884',
        'eu-west-1': '763104351884',
        'eu-central-1': '763104351884',
        'ap-southeast-1': '763104351884',
        'ap-southeast-2': '763104351884',
        'ap-northeast-1': '763104351884'
    }
    
    dlc_account = dlc_account_map.get(region, '763104351884')
    
    return f"{dlc_account}.dkr.ecr.{region}.amazonaws.com/tensorflow-inference:2.13-cpu"


def create_model_package(
    model_package_group: str,
    model_artifacts: str,
    inference_image_uri: str,
    training_job_name: str,
    metrics: dict
) -> str:
    """
    Create a model package in SageMaker Model Registry.
    """
    model_package_description = f"Pneumonia detection model from training job {training_job_name}"
    
    # Prepare model metrics for registry
    model_metrics = {
        'ModelQuality': {
            'Statistics': {
                'ContentType': 'application/json',
                'S3Uri': model_artifacts.replace('model.tar.gz', 'metrics.json')
            }
        }
    }
    
    # Create the model package
    response = sagemaker_client.create_model_package(
        ModelPackageGroupName=model_package_group,
        ModelPackageDescription=model_package_description,
        InferenceSpecification={
            'Containers': [
                {
                    'Image': inference_image_uri,
                    'ModelDataUrl': model_artifacts,
                    'Framework': 'TENSORFLOW',
                    'FrameworkVersion': '2.13',
                    'NearestModelName': 'pneumonia-detection'
                }
            ],
            'SupportedTransformInstanceTypes': ['ml.m5.large', 'ml.m5.xlarge'],
            'SupportedRealtimeInferenceInstanceTypes': ['ml.m5.large', 'ml.m5.xlarge'],
            'SupportedContentTypes': ['application/json', 'image/png'],
            'SupportedResponseMIMETypes': ['application/json']
        },
        ModelApprovalStatus='Approved',
        MetadataProperties={
            'GeneratedBy': 'HealthcareImagingMLOps',
            'ProjectId': 'pneumonia-detection'
        },
        CustomerMetadataProperties={
            'TrainingJobName': training_job_name,
            'Accuracy': str(metrics['accuracy']),
            'Precision': str(metrics['precision']),
            'Recall': str(metrics['recall']),
            'F1Score': str(metrics['f1_score']),
            'AUCROC': str(metrics['auc_roc']),
            'RegistrationTimestamp': datetime.utcnow().isoformat()
        }
    )
    
    return response['ModelPackageArn']


def emit_model_registered_event(model_package_arn: str, training_job_name: str, accuracy: float):
    """
    Emit a custom EventBridge event when model is registered.
    """
    try:
        event_bus_name = os.environ.get('EVENT_BUS_NAME', 'default')
        
        event_detail = {
            'modelPackageArn': model_package_arn,
            'trainingJobName': training_job_name,
            'accuracy': accuracy,
            'registrationTimestamp': datetime.utcnow().isoformat(),
            'status': 'REGISTERED'
        }
        
        response = events_client.put_events(
            Entries=[
                {
                    'Source': 'imaging.mlops',
                    'DetailType': 'ModelRegistered',
                    'Detail': json.dumps(event_detail),
                    'EventBusName': event_bus_name
                }
            ]
        )
        
        print(f"Emitted ModelRegistered event: {response}")
        
    except Exception as e:
        print(f"Error emitting event: {str(e)}")
        # Don't raise - model registration was successful
