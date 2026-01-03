"""
Healthcare Imaging MLOps Platform - HealthImaging Client
AWS HealthImaging API wrapper for DICOM image management
"""

import os
import json
import logging
from typing import Dict, List, Optional, Generator
import boto3
from botocore.config import Config

logger = logging.getLogger(__name__)


class HealthImagingClient:
    """Client for AWS HealthImaging service"""
    
    def __init__(
        self,
        datastore_id: str,
        region_name: str = None,
        config: Config = None
    ):
        """
        Initialize HealthImaging client.
        
        Args:
            datastore_id: HealthImaging datastore ID
            region_name: AWS region name
            config: Boto3 config object
        """
        self.datastore_id = datastore_id
        self.region_name = region_name or os.environ.get('AWS_REGION', 'us-east-1')
        
        if config is None:
            config = Config(
                retries={'max_attempts': 3, 'mode': 'adaptive'},
                connect_timeout=30,
                read_timeout=60
            )
        
        self.client = boto3.client(
            'medical-imaging',
            region_name=self.region_name,
            config=config
        )
    
    def get_datastore(self) -> Dict:
        """
        Get datastore information.
        
        Returns:
            Datastore details
        """
        response = self.client.get_datastore(datastoreId=self.datastore_id)
        return response['datastoreProperties']
    
    def list_image_sets(
        self,
        max_results: int = 100,
        search_criteria: Dict = None
    ) -> Generator[Dict, None, None]:
        """
        List image sets in the datastore.
        
        Args:
            max_results: Maximum results per page
            search_criteria: Optional search criteria
            
        Yields:
            Image set summaries
        """
        paginator = self.client.get_paginator('search_image_sets')
        
        params = {
            'datastoreId': self.datastore_id,
            'maxResults': max_results
        }
        
        if search_criteria:
            params['searchCriteria'] = search_criteria
        
        for page in paginator.paginate(**params):
            for image_set in page.get('imageSetsMetadataSummaries', []):
                yield image_set
    
    def get_image_set(self, image_set_id: str) -> Dict:
        """
        Get image set details.
        
        Args:
            image_set_id: Image set ID
            
        Returns:
            Image set details
        """
        response = self.client.get_image_set(
            datastoreId=self.datastore_id,
            imageSetId=image_set_id
        )
        return response
    
    def get_image_set_metadata(
        self,
        image_set_id: str,
        version_id: str = None
    ) -> Dict:
        """
        Get image set metadata.
        
        Args:
            image_set_id: Image set ID
            version_id: Optional version ID
            
        Returns:
            Image set metadata
        """
        params = {
            'datastoreId': self.datastore_id,
            'imageSetId': image_set_id
        }
        
        if version_id:
            params['versionId'] = version_id
        
        response = self.client.get_image_set_metadata(**params)
        
        # Parse the metadata blob
        metadata = json.loads(response['imageSetMetadataBlob'].read())
        return metadata
    
    def get_image_frame(
        self,
        image_set_id: str,
        image_frame_id: str
    ) -> bytes:
        """
        Get a single image frame.
        
        Args:
            image_set_id: Image set ID
            image_frame_id: Image frame ID
            
        Returns:
            Image frame data as bytes
        """
        response = self.client.get_image_frame(
            datastoreId=self.datastore_id,
            imageSetId=image_set_id,
            imageFrameInformation={'imageFrameId': image_frame_id}
        )
        
        return response['imageFrameBlob'].read()
    
    def start_dicom_import_job(
        self,
        job_name: str,
        input_s3_uri: str,
        output_s3_uri: str,
        data_access_role_arn: str
    ) -> Dict:
        """
        Start a DICOM import job.
        
        Args:
            job_name: Name for the import job
            input_s3_uri: S3 URI for input DICOM files
            output_s3_uri: S3 URI for import results
            data_access_role_arn: IAM role ARN for data access
            
        Returns:
            Import job details
        """
        response = self.client.start_dicom_import_job(
            datastoreId=self.datastore_id,
            jobName=job_name,
            inputS3Uri=input_s3_uri,
            outputS3Uri=output_s3_uri,
            dataAccessRoleArn=data_access_role_arn
        )
        
        logger.info(f"Started DICOM import job: {response['jobId']}")
        return response
    
    def get_dicom_import_job(self, job_id: str) -> Dict:
        """
        Get DICOM import job status.
        
        Args:
            job_id: Import job ID
            
        Returns:
            Import job details
        """
        response = self.client.get_dicom_import_job(
            datastoreId=self.datastore_id,
            jobId=job_id
        )
        return response['jobProperties']
    
    def list_dicom_import_jobs(
        self,
        status: str = None,
        max_results: int = 100
    ) -> Generator[Dict, None, None]:
        """
        List DICOM import jobs.
        
        Args:
            status: Optional status filter
            max_results: Maximum results per page
            
        Yields:
            Import job summaries
        """
        paginator = self.client.get_paginator('list_dicom_import_jobs')
        
        params = {
            'datastoreId': self.datastore_id,
            'maxResults': max_results
        }
        
        if status:
            params['jobStatus'] = status
        
        for page in paginator.paginate(**params):
            for job in page.get('jobSummaries', []):
                yield job
    
    def wait_for_import_job(
        self,
        job_id: str,
        poll_interval: int = 30,
        max_wait_time: int = 3600
    ) -> Dict:
        """
        Wait for DICOM import job to complete.
        
        Args:
            job_id: Import job ID
            poll_interval: Seconds between status checks
            max_wait_time: Maximum wait time in seconds
            
        Returns:
            Final job status
        """
        import time
        
        start_time = time.time()
        
        while True:
            job = self.get_dicom_import_job(job_id)
            status = job['jobStatus']
            
            if status in ['COMPLETED', 'FAILED']:
                return job
            
            elapsed = time.time() - start_time
            if elapsed > max_wait_time:
                raise TimeoutError(f"Import job {job_id} did not complete within {max_wait_time} seconds")
            
            logger.info(f"Import job {job_id} status: {status}. Waiting...")
            time.sleep(poll_interval)


class ImageStreamingClient:
    """Client for streaming images from HealthImaging"""
    
    def __init__(self, health_imaging_client: HealthImagingClient):
        """
        Initialize streaming client.
        
        Args:
            health_imaging_client: HealthImagingClient instance
        """
        self.client = health_imaging_client
    
    def stream_image_frames(
        self,
        image_set_id: str,
        frame_ids: List[str] = None
    ) -> Generator[bytes, None, None]:
        """
        Stream image frames from an image set.
        
        Args:
            image_set_id: Image set ID
            frame_ids: Optional list of specific frame IDs
            
        Yields:
            Image frame data
        """
        if frame_ids is None:
            # Get all frame IDs from metadata
            metadata = self.client.get_image_set_metadata(image_set_id)
            frame_ids = self._extract_frame_ids(metadata)
        
        for frame_id in frame_ids:
            yield self.client.get_image_frame(image_set_id, frame_id)
    
    def _extract_frame_ids(self, metadata: Dict) -> List[str]:
        """
        Extract frame IDs from image set metadata.
        
        Args:
            metadata: Image set metadata
            
        Returns:
            List of frame IDs
        """
        frame_ids = []
        
        # Navigate the DICOM metadata structure
        study = metadata.get('Study', {})
        for series in study.get('Series', {}).values():
            for instance in series.get('Instances', {}).values():
                for frame in instance.get('ImageFrames', []):
                    frame_ids.append(frame.get('ID'))
        
        return frame_ids
    
    def get_presigned_url(
        self,
        image_set_id: str,
        image_frame_id: str,
        expiration: int = 3600
    ) -> str:
        """
        Generate a presigned URL for image frame access.
        
        Args:
            image_set_id: Image set ID
            image_frame_id: Image frame ID
            expiration: URL expiration time in seconds
            
        Returns:
            Presigned URL
        """
        # Note: This is a simplified implementation
        # In production, use proper presigned URL generation
        return f"https://healthimaging.{self.client.region_name}.amazonaws.com/datastore/{self.client.datastore_id}/imageSet/{image_set_id}/frame/{image_frame_id}"


def create_client(datastore_id: str = None) -> HealthImagingClient:
    """
    Create a HealthImaging client from environment variables.
    
    Args:
        datastore_id: Optional datastore ID (defaults to env var)
        
    Returns:
        HealthImagingClient instance
    """
    if datastore_id is None:
        datastore_id = os.environ.get('HEALTHIMAGING_DATASTORE_ID')
        if not datastore_id:
            raise ValueError("HEALTHIMAGING_DATASTORE_ID environment variable not set")
    
    return HealthImagingClient(datastore_id)
