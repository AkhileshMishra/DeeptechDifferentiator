"""
Tests for the preprocessing module
"""

import os
import pytest
import numpy as np
from unittest.mock import Mock, patch, MagicMock


class TestDICOMPreprocessor:
    """Tests for DICOMPreprocessor class"""
    
    def test_normalize_image(self):
        """Test image normalization"""
        from src.pipeline.preprocessing import DICOMPreprocessor
        
        preprocessor = DICOMPreprocessor()
        
        # Test with simple array
        image = np.array([[0, 100], [200, 255]], dtype=np.float32)
        normalized = preprocessor.normalize_image(image)
        
        assert normalized.min() >= 0.0
        assert normalized.max() <= 1.0
        assert normalized.shape == image.shape
    
    def test_normalize_constant_image(self):
        """Test normalization with constant image"""
        from src.pipeline.preprocessing import DICOMPreprocessor
        
        preprocessor = DICOMPreprocessor()
        
        # Constant image should return zeros
        image = np.ones((100, 100), dtype=np.float32) * 128
        normalized = preprocessor.normalize_image(image)
        
        assert np.allclose(normalized, 0.0)
    
    def test_resize_image(self):
        """Test image resizing"""
        from src.pipeline.preprocessing import DICOMPreprocessor
        
        target_size = (256, 256)
        preprocessor = DICOMPreprocessor(target_size=target_size)
        
        # Create test image
        image = np.random.rand(512, 512).astype(np.float32)
        resized = preprocessor.resize_image(image)
        
        assert resized.shape == target_size
    
    def test_extract_metadata(self):
        """Test metadata extraction from DICOM"""
        from src.pipeline.preprocessing import DICOMPreprocessor
        
        preprocessor = DICOMPreprocessor()
        
        # Create mock DICOM dataset
        mock_dicom = Mock()
        mock_dicom.PatientID = "TEST123"
        mock_dicom.StudyDate = "20240101"
        mock_dicom.Modality = "CR"
        mock_dicom.BodyPartExamined = "CHEST"
        mock_dicom.Rows = 512
        mock_dicom.Columns = 512
        mock_dicom.BitsStored = 12
        mock_dicom.PhotometricInterpretation = "MONOCHROME2"
        
        metadata = preprocessor.extract_metadata(mock_dicom)
        
        assert metadata["patient_id"] == "TEST123"
        assert metadata["modality"] == "CR"
        assert metadata["rows"] == 512


class TestDataAugmenter:
    """Tests for DataAugmenter class"""
    
    def test_flip_horizontal(self):
        """Test horizontal flip"""
        from src.pipeline.preprocessing import DataAugmenter
        
        augmenter = DataAugmenter()
        
        image = np.array([[1, 2], [3, 4]], dtype=np.float32)
        flipped = augmenter.flip_horizontal(image)
        
        expected = np.array([[2, 1], [4, 3]], dtype=np.float32)
        assert np.array_equal(flipped, expected)
    
    def test_flip_vertical(self):
        """Test vertical flip"""
        from src.pipeline.preprocessing import DataAugmenter
        
        augmenter = DataAugmenter()
        
        image = np.array([[1, 2], [3, 4]], dtype=np.float32)
        flipped = augmenter.flip_vertical(image)
        
        expected = np.array([[3, 4], [1, 2]], dtype=np.float32)
        assert np.array_equal(flipped, expected)
    
    def test_adjust_brightness(self):
        """Test brightness adjustment"""
        from src.pipeline.preprocessing import DataAugmenter
        
        augmenter = DataAugmenter()
        
        image = np.array([[0.5, 0.5], [0.5, 0.5]], dtype=np.float32)
        
        # Increase brightness
        brightened = augmenter.adjust_brightness(image, 1.5)
        assert brightened.max() == 0.75
        
        # Decrease brightness
        darkened = augmenter.adjust_brightness(image, 0.5)
        assert darkened.max() == 0.25
    
    def test_brightness_clipping(self):
        """Test that brightness adjustment clips to [0, 1]"""
        from src.pipeline.preprocessing import DataAugmenter
        
        augmenter = DataAugmenter()
        
        image = np.array([[0.8, 0.9], [0.7, 1.0]], dtype=np.float32)
        brightened = augmenter.adjust_brightness(image, 2.0)
        
        assert brightened.max() <= 1.0
        assert brightened.min() >= 0.0


class TestTrainTestSplit:
    """Tests for train/test split functionality"""
    
    @patch('glob.glob')
    @patch('shutil.copy2')
    @patch('os.makedirs')
    def test_create_train_test_split(self, mock_makedirs, mock_copy, mock_glob):
        """Test train/test split creation"""
        from src.pipeline.preprocessing import create_train_test_split
        
        # Mock file list
        mock_glob.return_value = [f"/data/image_{i}.dcm" for i in range(100)]
        
        splits = create_train_test_split(
            "/data",
            "/output",
            test_ratio=0.2,
            validation_ratio=0.1
        )
        
        # Check split sizes
        total = len(splits["train"]) + len(splits["validation"]) + len(splits["test"])
        assert total == 100
        
        # Check approximate ratios
        assert len(splits["test"]) == pytest.approx(20, abs=5)
        assert len(splits["validation"]) == pytest.approx(10, abs=5)


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
