"""
Tests for the HealthImaging client module
"""

import os
import pytest
from unittest.mock import Mock, patch, MagicMock
import json


class TestHealthImagingClient:
    """Tests for HealthImagingClient class"""
    
    @patch('boto3.client')
    def test_client_initialization(self, mock_boto_client):
        """Test client initialization"""
        from src.healthimaging.client import HealthImagingClient
        
        client = HealthImagingClient(
            datastore_id="test-datastore-id",
            region_name="us-east-1"
        )
        
        assert client.datastore_id == "test-datastore-id"
        assert client.region_name == "us-east-1"
        mock_boto_client.assert_called_once()
    
    @patch('boto3.client')
    def test_get_datastore(self, mock_boto_client):
        """Test get_datastore method"""
        from src.healthimaging.client import HealthImagingClient
        
        # Setup mock
        mock_client_instance = Mock()
        mock_client_instance.get_datastore.return_value = {
            'datastoreProperties': {
                'datastoreId': 'test-id',
                'datastoreName': 'test-datastore',
                'datastoreStatus': 'ACTIVE'
            }
        }
        mock_boto_client.return_value = mock_client_instance
        
        client = HealthImagingClient(datastore_id="test-id")
        result = client.get_datastore()
        
        assert result['datastoreId'] == 'test-id'
        assert result['datastoreStatus'] == 'ACTIVE'
    
    @patch('boto3.client')
    def test_get_image_set(self, mock_boto_client):
        """Test get_image_set method"""
        from src.healthimaging.client import HealthImagingClient
        
        # Setup mock
        mock_client_instance = Mock()
        mock_client_instance.get_image_set.return_value = {
            'imageSetId': 'test-image-set-id',
            'imageSetState': 'ACTIVE'
        }
        mock_boto_client.return_value = mock_client_instance
        
        client = HealthImagingClient(datastore_id="test-datastore-id")
        result = client.get_image_set("test-image-set-id")
        
        assert result['imageSetId'] == 'test-image-set-id'
        mock_client_instance.get_image_set.assert_called_once_with(
            datastoreId="test-datastore-id",
            imageSetId="test-image-set-id"
        )
    
    @patch('boto3.client')
    def test_start_dicom_import_job(self, mock_boto_client):
        """Test starting a DICOM import job"""
        from src.healthimaging.client import HealthImagingClient
        
        # Setup mock
        mock_client_instance = Mock()
        mock_client_instance.start_dicom_import_job.return_value = {
            'jobId': 'test-job-id',
            'jobStatus': 'SUBMITTED'
        }
        mock_boto_client.return_value = mock_client_instance
        
        client = HealthImagingClient(datastore_id="test-datastore-id")
        result = client.start_dicom_import_job(
            job_name="test-import",
            input_s3_uri="s3://bucket/input/",
            output_s3_uri="s3://bucket/output/",
            data_access_role_arn="arn:aws:iam::123456789012:role/test-role"
        )
        
        assert result['jobId'] == 'test-job-id'
    
    @patch('boto3.client')
    def test_get_dicom_import_job(self, mock_boto_client):
        """Test getting DICOM import job status"""
        from src.healthimaging.client import HealthImagingClient
        
        # Setup mock
        mock_client_instance = Mock()
        mock_client_instance.get_dicom_import_job.return_value = {
            'jobProperties': {
                'jobId': 'test-job-id',
                'jobStatus': 'COMPLETED'
            }
        }
        mock_boto_client.return_value = mock_client_instance
        
        client = HealthImagingClient(datastore_id="test-datastore-id")
        result = client.get_dicom_import_job("test-job-id")
        
        assert result['jobStatus'] == 'COMPLETED'


class TestImageStreamingClient:
    """Tests for ImageStreamingClient class"""
    
    @patch('boto3.client')
    def test_extract_frame_ids(self, mock_boto_client):
        """Test frame ID extraction from metadata"""
        from src.healthimaging.client import HealthImagingClient, ImageStreamingClient
        
        mock_boto_client.return_value = Mock()
        
        hi_client = HealthImagingClient(datastore_id="test-id")
        streaming_client = ImageStreamingClient(hi_client)
        
        metadata = {
            'Study': {
                'Series': {
                    'series1': {
                        'Instances': {
                            'instance1': {
                                'ImageFrames': [
                                    {'ID': 'frame1'},
                                    {'ID': 'frame2'}
                                ]
                            }
                        }
                    }
                }
            }
        }
        
        frame_ids = streaming_client._extract_frame_ids(metadata)
        
        assert len(frame_ids) == 2
        assert 'frame1' in frame_ids
        assert 'frame2' in frame_ids


class TestCreateClient:
    """Tests for create_client factory function"""
    
    @patch.dict(os.environ, {'HEALTHIMAGING_DATASTORE_ID': 'env-datastore-id'})
    @patch('boto3.client')
    def test_create_client_from_env(self, mock_boto_client):
        """Test client creation from environment variable"""
        from src.healthimaging.client import create_client
        
        mock_boto_client.return_value = Mock()
        
        client = create_client()
        
        assert client.datastore_id == 'env-datastore-id'
    
    @patch('boto3.client')
    def test_create_client_with_explicit_id(self, mock_boto_client):
        """Test client creation with explicit datastore ID"""
        from src.healthimaging.client import create_client
        
        mock_boto_client.return_value = Mock()
        
        client = create_client(datastore_id="explicit-id")
        
        assert client.datastore_id == 'explicit-id'
    
    @patch.dict(os.environ, {}, clear=True)
    def test_create_client_missing_env(self):
        """Test error when environment variable is missing"""
        from src.healthimaging.client import create_client
        
        # Remove the env var if it exists
        os.environ.pop('HEALTHIMAGING_DATASTORE_ID', None)
        
        with pytest.raises(ValueError, match="HEALTHIMAGING_DATASTORE_ID"):
            create_client()


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
