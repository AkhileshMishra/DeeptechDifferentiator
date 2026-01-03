"""
Healthcare Imaging MLOps Platform - Preprocessing Module
Handles DICOM image preprocessing for model training
"""

import os
import json
import logging
from typing import Dict, List, Tuple, Optional
import numpy as np
from PIL import Image
import pydicom
from pydicom.pixel_data_handlers.util import apply_voi_lut

logger = logging.getLogger(__name__)


class DICOMPreprocessor:
    """Preprocessor for DICOM medical images"""
    
    def __init__(
        self,
        target_size: Tuple[int, int] = (512, 512),
        normalize: bool = True,
        apply_windowing: bool = True
    ):
        """
        Initialize the DICOM preprocessor.
        
        Args:
            target_size: Target image dimensions (height, width)
            normalize: Whether to normalize pixel values to [0, 1]
            apply_windowing: Whether to apply DICOM windowing
        """
        self.target_size = target_size
        self.normalize = normalize
        self.apply_windowing = apply_windowing
    
    def load_dicom(self, file_path: str) -> pydicom.Dataset:
        """
        Load a DICOM file.
        
        Args:
            file_path: Path to the DICOM file
            
        Returns:
            pydicom Dataset object
        """
        logger.info(f"Loading DICOM file: {file_path}")
        return pydicom.dcmread(file_path)
    
    def extract_pixel_array(self, dicom: pydicom.Dataset) -> np.ndarray:
        """
        Extract pixel array from DICOM dataset.
        
        Args:
            dicom: pydicom Dataset object
            
        Returns:
            Numpy array of pixel values
        """
        if self.apply_windowing:
            pixel_array = apply_voi_lut(dicom.pixel_array, dicom)
        else:
            pixel_array = dicom.pixel_array
        
        return pixel_array.astype(np.float32)
    
    def normalize_image(self, image: np.ndarray) -> np.ndarray:
        """
        Normalize image pixel values to [0, 1] range.
        
        Args:
            image: Input image array
            
        Returns:
            Normalized image array
        """
        min_val = image.min()
        max_val = image.max()
        
        if max_val - min_val > 0:
            normalized = (image - min_val) / (max_val - min_val)
        else:
            normalized = np.zeros_like(image)
        
        return normalized
    
    def resize_image(self, image: np.ndarray) -> np.ndarray:
        """
        Resize image to target dimensions.
        
        Args:
            image: Input image array
            
        Returns:
            Resized image array
        """
        pil_image = Image.fromarray((image * 255).astype(np.uint8))
        resized = pil_image.resize(self.target_size, Image.Resampling.LANCZOS)
        return np.array(resized).astype(np.float32) / 255.0
    
    def preprocess(self, file_path: str) -> np.ndarray:
        """
        Full preprocessing pipeline for a DICOM file.
        
        Args:
            file_path: Path to the DICOM file
            
        Returns:
            Preprocessed image array
        """
        # Load DICOM
        dicom = self.load_dicom(file_path)
        
        # Extract pixel array
        image = self.extract_pixel_array(dicom)
        
        # Normalize
        if self.normalize:
            image = self.normalize_image(image)
        
        # Resize
        image = self.resize_image(image)
        
        # Add channel dimension if needed
        if len(image.shape) == 2:
            image = np.expand_dims(image, axis=-1)
        
        return image
    
    def extract_metadata(self, dicom: pydicom.Dataset) -> Dict:
        """
        Extract relevant metadata from DICOM dataset.
        
        Args:
            dicom: pydicom Dataset object
            
        Returns:
            Dictionary of metadata
        """
        metadata = {
            "patient_id": str(getattr(dicom, "PatientID", "Unknown")),
            "study_date": str(getattr(dicom, "StudyDate", "Unknown")),
            "modality": str(getattr(dicom, "Modality", "Unknown")),
            "body_part": str(getattr(dicom, "BodyPartExamined", "Unknown")),
            "rows": int(getattr(dicom, "Rows", 0)),
            "columns": int(getattr(dicom, "Columns", 0)),
            "bits_stored": int(getattr(dicom, "BitsStored", 0)),
            "photometric_interpretation": str(getattr(dicom, "PhotometricInterpretation", "Unknown"))
        }
        return metadata


class DataAugmenter:
    """Data augmentation for medical images"""
    
    def __init__(
        self,
        rotation_range: float = 15.0,
        horizontal_flip: bool = True,
        vertical_flip: bool = False,
        zoom_range: Tuple[float, float] = (0.9, 1.1),
        brightness_range: Tuple[float, float] = (0.9, 1.1)
    ):
        """
        Initialize data augmenter.
        
        Args:
            rotation_range: Maximum rotation angle in degrees
            horizontal_flip: Whether to apply horizontal flipping
            vertical_flip: Whether to apply vertical flipping
            zoom_range: Range for random zoom
            brightness_range: Range for brightness adjustment
        """
        self.rotation_range = rotation_range
        self.horizontal_flip = horizontal_flip
        self.vertical_flip = vertical_flip
        self.zoom_range = zoom_range
        self.brightness_range = brightness_range
    
    def rotate(self, image: np.ndarray, angle: float) -> np.ndarray:
        """Apply rotation to image"""
        pil_image = Image.fromarray((image * 255).astype(np.uint8))
        rotated = pil_image.rotate(angle, resample=Image.Resampling.BILINEAR, fillcolor=0)
        return np.array(rotated).astype(np.float32) / 255.0
    
    def flip_horizontal(self, image: np.ndarray) -> np.ndarray:
        """Apply horizontal flip"""
        return np.fliplr(image)
    
    def flip_vertical(self, image: np.ndarray) -> np.ndarray:
        """Apply vertical flip"""
        return np.flipud(image)
    
    def adjust_brightness(self, image: np.ndarray, factor: float) -> np.ndarray:
        """Adjust image brightness"""
        return np.clip(image * factor, 0, 1)
    
    def augment(self, image: np.ndarray) -> np.ndarray:
        """
        Apply random augmentations to image.
        
        Args:
            image: Input image array
            
        Returns:
            Augmented image array
        """
        # Random rotation
        if self.rotation_range > 0:
            angle = np.random.uniform(-self.rotation_range, self.rotation_range)
            if len(image.shape) == 3:
                image = self.rotate(image[:, :, 0], angle)
                image = np.expand_dims(image, axis=-1)
            else:
                image = self.rotate(image, angle)
        
        # Random horizontal flip
        if self.horizontal_flip and np.random.random() > 0.5:
            image = self.flip_horizontal(image)
        
        # Random vertical flip
        if self.vertical_flip and np.random.random() > 0.5:
            image = self.flip_vertical(image)
        
        # Random brightness adjustment
        if self.brightness_range != (1.0, 1.0):
            factor = np.random.uniform(*self.brightness_range)
            image = self.adjust_brightness(image, factor)
        
        return image


def create_train_test_split(
    data_dir: str,
    output_dir: str,
    test_ratio: float = 0.2,
    validation_ratio: float = 0.1
) -> Dict[str, List[str]]:
    """
    Create train/validation/test split from data directory.
    
    Args:
        data_dir: Input data directory
        output_dir: Output directory for split data
        test_ratio: Ratio of data for testing
        validation_ratio: Ratio of data for validation
        
    Returns:
        Dictionary with file paths for each split
    """
    import glob
    import shutil
    from sklearn.model_selection import train_test_split
    
    # Find all DICOM files
    dicom_files = glob.glob(os.path.join(data_dir, "**/*.dcm"), recursive=True)
    logger.info(f"Found {len(dicom_files)} DICOM files")
    
    # Split data
    train_files, test_files = train_test_split(
        dicom_files, test_size=test_ratio, random_state=42
    )
    train_files, val_files = train_test_split(
        train_files, test_size=validation_ratio / (1 - test_ratio), random_state=42
    )
    
    # Create output directories
    splits = {
        "train": train_files,
        "validation": val_files,
        "test": test_files
    }
    
    for split_name, files in splits.items():
        split_dir = os.path.join(output_dir, split_name)
        os.makedirs(split_dir, exist_ok=True)
        
        for file_path in files:
            dest_path = os.path.join(split_dir, os.path.basename(file_path))
            shutil.copy2(file_path, dest_path)
    
    logger.info(f"Split complete: train={len(train_files)}, val={len(val_files)}, test={len(test_files)}")
    
    return splits


if __name__ == "__main__":
    # Entry point for SageMaker Processing Job
    import argparse
    
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-dir", type=str, default="/opt/ml/processing/input")
    parser.add_argument("--output-dir", type=str, default="/opt/ml/processing/output")
    parser.add_argument("--target-size", type=int, default=512)
    args = parser.parse_args()
    
    # Initialize preprocessor
    preprocessor = DICOMPreprocessor(target_size=(args.target_size, args.target_size))
    augmenter = DataAugmenter()
    
    # Create train/test split
    splits = create_train_test_split(
        args.input_dir,
        args.output_dir,
        test_ratio=0.2,
        validation_ratio=0.1
    )
    
    print(f"Preprocessing complete. Output saved to {args.output_dir}")
