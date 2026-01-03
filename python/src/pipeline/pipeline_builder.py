# ============================================================================
# SAGEMAKER PIPELINE DEFINITION (Python)
# healthcare/imaging/mlops/python/src/pipeline/pipeline_builder.py
# ============================================================================

"""
SageMaker Pipeline Definition for Pneumonia Detection Model
Implements the automated training CI/CD workflow triggered by new imaging data
"""

import json
import logging
from typing import Dict, Any, Optional, List
from datetime import datetime

import boto3
from sagemaker.estimator import Estimator
from sagemaker.processing import ScriptProcessor
from sagemaker.workflow.pipeline import Pipeline
from sagemaker.workflow.steps import (
    ProcessingStep,
    TrainingStep,
    EvaluationStep,
    CreateModelStep,
)
from sagemaker.workflow.parameters import (
    ParameterString,
    ParameterInteger,
    ParameterFloat,
)
from sagemaker.workflow.conditions import ConditionGreaterThan
from sagemaker.workflow.condition_step import ConditionStep
from sagemaker.model_metrics import ModelMetrics, MetricsSource
from sagemaker.model import Model
from sagemaker.image_uris import image_uri

logger = logging.getLogger(__name__)


class PneumoniaDetectionPipeline:
    """
    Build and manage SageMaker Pipeline for pneumonia detection model training
    
    Workflow:
    1. Data preprocessing (normalize, augment, validate)
    2. Model training (distributed on GPU)
    3. Model evaluation (accuracy, recall, precision on test set)
    4. Conditional approval (register if accuracy > threshold)
    5. Model packaging (for batch and real-time inference)
    """

    def __init__(
        self,
        role_arn: str,
        pipeline_name: str,
        s3_base_path: str,
        sagemaker_session=None,
        region: Optional[str] = None,
    ):
        """
        Initialize pipeline builder
        
        Args:
            role_arn: SageMaker execution role ARN
            pipeline_name: Name of the SageMaker pipeline
            s3_base_path: Base S3 path for artifacts (s3://bucket/prefix)
            sagemaker_session: Optional SageMaker session
            region: AWS region
        """
        self.role_arn = role_arn
        self.pipeline_name = pipeline_name
        self.s3_base_path = s3_base_path
        self.region = region or "us-east-1"
        
        if sagemaker_session:
            self.sagemaker_session = sagemaker_session
        else:
            import sagemaker as sm
            self.sagemaker_session = sm.Session()

        self.sagemaker_client = boto3.client("sagemaker", region_name=self.region)
        self.s3_client = boto3.client("s3", region_name=self.region)
        self.cloudwatch_client = boto3.client(
            "cloudwatch", region_name=self.region
        )

    def _define_parameters(self) -> Dict[str, Any]:
        """Define pipeline parameters for dynamic execution"""
        
        return {
            "training_data_path": ParameterString(
                name="TrainingDataPath",
                default_value=f"{self.s3_base_path}/training-data",
            ),
            "test_data_path": ParameterString(
                name="TestDataPath",
                default_value=f"{self.s3_base_path}/test-data",
            ),
            "model_approval_status": ParameterString(
                name="ModelApprovalStatus",
                default_value="Approved",
            ),
            "training_instance_count": ParameterInteger(
                name="TrainingInstanceCount",
                default_value=1,
            ),
            "training_instance_type": ParameterString(
                name="TrainingInstanceType",
                default_value="ml.p3.2xlarge",
            ),
            "processing_instance_count": ParameterInteger(
                name="ProcessingInstanceCount",
                default_value=1,
            ),
            "processing_instance_type": ParameterString(
                name="ProcessingInstanceType",
                default_value="ml.m5.2xlarge",
            ),
            "accuracy_threshold": ParameterFloat(
                name="AccuracyThreshold",
                default_value=0.85,
            ),
        }

    def _create_preprocessing_step(
        self, params: Dict[str, Any]
    ) -> ProcessingStep:
        """
        Create data preprocessing step
        
        Normalizes DICOM images, applies augmentation, validates data quality
        """
        
        # Use built-in SageMaker Processing container or custom container
        script_processor = ScriptProcessor(
            image_uri=f"{self.sagemaker_session.default_bucket()}/processing:latest",
            role=self.role_arn,
            instance_count=params["processing_instance_count"],
            instance_type=params["processing_instance_type"],
            sagemaker_session=self.sagemaker_session,
        )

        processing_step = ProcessingStep(
            name="PreprocessDICOMImages",
            processor=script_processor,
            job_arguments=[
                "--input-path",
                params["training_data_path"],
                "--output-path",
                f"{self.s3_base_path}/preprocessed-data",
                "--normalization-method",
                "standardize",
                "--augmentation-factor",
                "2",
            ],
            code="preprocessing.py",
        )

        return processing_step

    def _create_training_step(
        self,
        params: Dict[str, Any],
        preprocessing_step: ProcessingStep,
    ) -> TrainingStep:
        """
        Create model training step
        
        Trains ResNet-based pneumonia detector on preprocessed DICOM images
        Uses distributed training on GPU instances
        """

        # Training estimator configuration
        estimator = Estimator(
            image_uri=f"{self.sagemaker_session.default_bucket()}/training:latest",
            role=self.role_arn,
            instance_count=params["training_instance_count"],
            instance_type=params["training_instance_type"],
            output_path=f"{self.s3_base_path}/model-artifacts",
            sagemaker_session=self.sagemaker_session,
            base_job_name="pneumonia-detector",
            use_spot_instances=False,  # Set to True for cost optimization
        )

        # Hyperparameters
        estimator.set_hyperparameters(
            epochs=50,
            batch_size=32,
            learning_rate=0.001,
            optimizer="adam",
            validation_split=0.2,
            early_stopping_patience=5,
            model_architecture="resnet50",
            input_shape="512,512,1",  # Single-channel DICOM
        )

        training_step = TrainingStep(
            name="TrainPneumoniaDetector",
            estimator=estimator,
            inputs={
                "training": params["training_data_path"],
            },
        )

        return training_step

    def _create_evaluation_step(
        self,
        params: Dict[str, Any],
        training_step: TrainingStep,
    ) -> EvaluationStep:
        """
        Create model evaluation step
        
        Evaluates trained model on held-out test set
        Computes accuracy, precision, recall, F1-score
        """

        # Evaluation script
        evaluation_report_path = (
            f"{self.s3_base_path}/evaluation-reports"
        )

        script_processor = ScriptProcessor(
            image_uri=f"{self.sagemaker_session.default_bucket()}/evaluation:latest",
            role=self.role_arn,
            instance_count=1,
            instance_type="ml.m5.xlarge",
            sagemaker_session=self.sagemaker_session,
        )

        evaluation_step = EvaluationStep(
            name="EvaluatePneumoniaModel",
            processor=script_processor,
            job_arguments=[
                "--model-path",
                training_step.properties.ModelArtifacts.S3ModelArtifacts,
                "--test-data-path",
                params["test_data_path"],
                "--output-path",
                evaluation_report_path,
            ],
            code="evaluation.py",
            property_files=[
                PropertyFile(
                    name="PneumoniaEvaluationReport",
                    output_name="evaluation",
                    path="evaluation.json",
                )
            ],
        )

        return evaluation_step

    def _create_model_registration_condition(
        self,
        evaluation_step: EvaluationStep,
        accuracy_threshold: ParameterFloat,
    ) -> ConditionStep:
        """
        Create conditional step for automatic model approval
        
        Only registers model if accuracy exceeds threshold
        """

        accuracy_condition = ConditionGreaterThan(
            left=evaluation_step.properties.EvaluationReport.accuracy,
            right=accuracy_threshold,
        )

        condition_step = ConditionStep(
            name="ApproveOrRejectModel",
            conditions=[accuracy_condition],
            if_steps=[],  # Will add model creation step
            else_steps=[],  # Optional: add logging step
        )

        return condition_step

    def build_pipeline(self) -> Pipeline:
        """Build complete SageMaker pipeline"""

        params = self._define_parameters()

        # Step 1: Preprocessing
        preprocessing_step = self._create_preprocessing_step(params)

        # Step 2: Training
        training_step = self._create_training_step(params, preprocessing_step)

        # Step 3: Evaluation
        evaluation_step = self._create_evaluation_step(params, training_step)

        # Step 4: Conditional Model Registration
        condition_step = self._create_model_registration_condition(
            evaluation_step,
            params["accuracy_threshold"],
        )

        # Create pipeline
        pipeline = Pipeline(
            name=self.pipeline_name,
            parameters=[
                params["training_data_path"],
                params["test_data_path"],
                params["model_approval_status"],
                params["training_instance_count"],
                params["training_instance_type"],
                params["processing_instance_count"],
                params["processing_instance_type"],
                params["accuracy_threshold"],
            ],
            steps=[
                preprocessing_step,
                training_step,
                evaluation_step,
                condition_step,
            ],
        )

        return pipeline

    def deploy_pipeline(self) -> Dict[str, Any]:
        """Deploy pipeline to SageMaker"""

        pipeline = self.build_pipeline()

        # Upsert (create or update) the pipeline
        pipeline.upsert(
            role_arn=self.role_arn,
            description="Automated pneumonia detection model training pipeline",
        )

        logger.info(f"Pipeline '{self.pipeline_name}' deployed successfully")

        return {
            "pipeline_arn": pipeline.describe()["PipelineArn"],
            "pipeline_name": self.pipeline_name,
            "status": "Active",
            "created_at": datetime.utcnow().isoformat(),
        }

    def start_pipeline_execution(
        self, execution_name: str, parameters: Optional[Dict[str, str]] = None
    ) -> Dict[str, Any]:
        """
        Start a pipeline execution with optional parameter overrides
        
        Args:
            execution_name: Unique execution name
            parameters: Optional parameter overrides
            
        Returns:
            Execution metadata
        """

        execution_params = {}
        if parameters:
            execution_params.update(parameters)

        response = self.sagemaker_client.start_pipeline_execution(
            PipelineName=self.pipeline_name,
            PipelineExecutionDisplayName=execution_name,
            PipelineParameters=[
                {"Name": k, "Value": str(v)}
                for k, v in execution_params.items()
            ],
        )

        logger.info(f"Pipeline execution started: {response['PipelineExecutionArn']}")

        return {
            "pipeline_execution_arn": response["PipelineExecutionArn"],
            "execution_name": execution_name,
            "status": "Executing",
            "started_at": datetime.utcnow().isoformat(),
        }

    def get_pipeline_status(self, execution_name: str) -> Dict[str, Any]:
        """Get current pipeline execution status"""

        response = self.sagemaker_client.describe_pipeline_execution(
            PipelineExecutionArn=f"arn:aws:sagemaker:{self.region}:account-id:pipeline/{self.pipeline_name}/execution/{execution_name}"
        )

        return {
            "execution_name": execution_name,
            "status": response["PipelineExecutionStatus"],
            "created_time": response["CreationTime"].isoformat(),
            "failure_reason": response.get("PipelineExecutionFailureReason"),
        }


# ============================================================================
# LAMBDA HANDLER FOR PIPELINE TRIGGER
# healthcare/imaging/mlops/python/src/lambda_handlers/pipeline_trigger.py
# ============================================================================

"""
Lambda handler to trigger SageMaker pipeline when image is verified
"""

import json
import logging
import os
from datetime import datetime

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

sagemaker_client = boto3.client("sagemaker")
cloudwatch_client = boto3.client("cloudwatch")


def lambda_handler(event, context):
    """
    Trigger SageMaker pipeline execution when DICOM image is verified
    
    Event format (from EventBridge):
    {
        "source": "aws.healthimaging",
        "detail-type": "HealthImaging ImageVerified",
        "detail": {
            "dataStoreId": "...",
            "imageSets": [{
                "imageSetId": "...",
                "patientInfo": {...}
            }],
            "verificationTime": "...",
            "verifiedBy": "..."
        }
    }
    """

    try:
        # Extract image metadata
        detail = event.get("detail", {})
        data_store_id = detail.get("dataStoreId")
        image_sets = detail.get("imageSets", [])
        verified_by = detail.get("verifiedBy")
        verification_time = detail.get("verificationTime")

        if not image_sets:
            logger.warning("No image sets found in event")
            return {
                "statusCode": 400,
                "body": json.dumps({"error": "No image sets provided"}),
            }

        # Prepare training data location
        image_set_id = image_sets[0]["imageSetId"]
        training_data_path = (
            f"s3://{os.environ['TRAINING_BUCKET']}/verified/{image_set_id}/"
        )

        # Start SageMaker pipeline execution
        pipeline_name = os.environ["SAGEMAKER_PIPELINE_NAME"]
        execution_name = f"execution-{image_set_id}-{int(datetime.utcnow().timestamp())}"

        response = sagemaker_client.start_pipeline_execution(
            PipelineName=pipeline_name,
            PipelineExecutionDisplayName=execution_name,
            PipelineParameters=[
                {
                    "Name": "TrainingDataPath",
                    "Value": training_data_path,
                },
                {
                    "Name": "VerifiedBy",
                    "Value": verified_by,
                },
            ],
        )

        execution_arn = response["PipelineExecutionArn"]

        logger.info(
            f"Pipeline execution started: {execution_arn} for image {image_set_id}"
        )

        # Publish metric to CloudWatch
        cloudwatch_client.put_metric_data(
            Namespace=f"{os.environ['PROJECT_NAME']}/Pipeline",
            MetricData=[
                {
                    "MetricName": "PipelineExecutionsTriggered",
                    "Value": 1,
                    "Unit": "Count",
                    "Timestamp": datetime.utcnow(),
                },
            ],
        )

        return {
            "statusCode": 200,
            "body": json.dumps(
                {
                    "execution_arn": execution_arn,
                    "execution_name": execution_name,
                    "image_set_id": image_set_id,
                    "status": "execution_started",
                }
            ),
        }

    except Exception as e:
        logger.error(f"Error triggering pipeline: {str(e)}", exc_info=True)

        # Publish error metric
        cloudwatch_client.put_metric_data(
            Namespace=f"{os.environ['PROJECT_NAME']}/Pipeline",
            MetricData=[
                {
                    "MetricName": "PipelineTriggerErrors",
                    "Value": 1,
                    "Unit": "Count",
                    "Timestamp": datetime.utcnow(),
                },
            ],
        )

        return {
            "statusCode": 500,
            "body": json.dumps({"error": str(e)}),
        }
