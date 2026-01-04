import sys
import pydicom
from pydicom.dataset import FileDataset
from pydicom.uid import ExplicitVRLittleEndian
import pydicom._storage_sopclass_uids
import datetime
import numpy as np
import os

def create_dicom(filename="sample-chest-ct.dcm"):
    # Create file meta information
    file_meta = pydicom.dataset.FileMetaDataset()
    file_meta.MediaStorageSOPClassUID = pydicom._storage_sopclass_uids.CTImageStorage
    file_meta.MediaStorageSOPInstanceUID = pydicom.uid.generate_uid()
    file_meta.TransferSyntaxUID = ExplicitVRLittleEndian

    # Create the dataset
    ds = FileDataset(filename, {}, file_meta=file_meta, preamble=b"\0" * 128)

    # Add required elements
    ds.PatientName = "TEST^PATIENT"
    ds.PatientID = "123456"
    ds.Modality = "CT"
    ds.StudyDate = datetime.datetime.now().strftime('%Y%m%d')
    ds.StudyTime = datetime.datetime.now().strftime('%H%M%S')
    
    # Image properties (Small size for demo speed, but logic holds for large)
    ds.Rows = 512
    ds.Columns = 512
    ds.BitsAllocated = 16
    ds.BitsStored = 12
    ds.HighBit = 11
    ds.PixelRepresentation = 0
    ds.SamplesPerPixel = 1
    ds.PhotometricInterpretation = "MONOCHROME2"
    
    # Generate random pixel data (Noise simulating a scan)
    pixel_data = np.random.randint(0, 1000, (512, 512), dtype=np.uint16)
    ds.PixelData = pixel_data.tobytes()
    
    # Save
    ds.is_little_endian = True
    ds.is_implicit_VR = False
    ds.save_as(filename)
    print(f"Generated {filename}")

if __name__ == "__main__":
    output_file = sys.argv[1] if len(sys.argv) > 1 else "sample.dcm"
    create_dicom(output_file)
