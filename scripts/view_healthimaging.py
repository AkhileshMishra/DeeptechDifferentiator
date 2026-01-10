#!/usr/bin/env python3
"""
Quick script to download and view an image from AWS HealthImaging.
Run this in AWS CloudShell or locally with AWS credentials.

Usage:
    python view_healthimaging.py <datastore_id> <image_set_id>
    
Example:
    python view_healthimaging.py 2c5ad42eef2b4f82a7fe3e8905006d68 386323fe245415294a8647b99747ebed
"""

import boto3
import json
import gzip
import sys

def main():
    if len(sys.argv) < 3:
        print("Usage: python view_healthimaging.py <datastore_id> <image_set_id>")
        print("Example: python view_healthimaging.py 2c5ad42eef2b4f82a7fe3e8905006d68 386323fe245415294a8647b99747ebed")
        sys.exit(1)
    
    datastore_id = sys.argv[1]
    image_set_id = sys.argv[2]
    
    ahi = boto3.client('medical-imaging')
    
    print(f"Fetching metadata for image set: {image_set_id}")
    
    # Get metadata
    metadata_response = ahi.get_image_set_metadata(
        datastoreId=datastore_id,
        imageSetId=image_set_id
    )
    
    metadata_blob = metadata_response['imageSetMetadataBlob'].read()
    
    # Decompress if gzipped
    if metadata_blob[:2] == b'\x1f\x8b':
        metadata_blob = gzip.decompress(metadata_blob)
    
    metadata = json.loads(metadata_blob.decode('utf-8'))
    
    print("\n=== DICOM Metadata ===")
    print(json.dumps(metadata, indent=2, default=str)[:2000])
    print("...")
    
    # Extract frame info
    study = metadata.get('Study', {})
    for series_id, series in study.get('Series', {}).items():
        for instance_id, instance in series.get('Instances', {}).items():
            dicom = instance.get('DICOM', {})
            frames = instance.get('ImageFrames', [])
            
            print(f"\n=== Image Info ===")
            print(f"Rows: {dicom.get('Rows')}")
            print(f"Columns: {dicom.get('Columns')}")
            print(f"Bits Allocated: {dicom.get('BitsAllocated')}")
            print(f"Bits Stored: {dicom.get('BitsStored')}")
            print(f"Photometric Interpretation: {dicom.get('PhotometricInterpretation')}")
            print(f"Number of Frames: {len(frames)}")
            
            if frames:
                frame_id = frames[0].get('ID')
                print(f"\nFetching frame: {frame_id}")
                
                # Get frame
                frame_response = ahi.get_image_frame(
                    datastoreId=datastore_id,
                    imageSetId=image_set_id,
                    imageFrameInformation={'imageFrameId': frame_id}
                )
                
                frame_data = frame_response['imageFrameBlob'].read()
                
                print(f"Frame size: {len(frame_data)} bytes")
                print(f"First 50 bytes (hex): {frame_data[:50].hex()}")
                
                # Check if it's HTJ2K (starts with JPEG 2000 signature)
                if frame_data[:4] == b'\xff\x4f\xff\x51':
                    print("Format: JPEG 2000 codestream (J2K)")
                elif frame_data[:12] == b'\x00\x00\x00\x0c\x6a\x50\x20\x20\x0d\x0a\x87\x0a':
                    print("Format: JPEG 2000 (JP2)")
                else:
                    print(f"Format: Unknown (magic bytes: {frame_data[:4].hex()})")
                
                # Save to file
                output_file = f"frame_{image_set_id[:8]}.j2k"
                with open(output_file, 'wb') as f:
                    f.write(frame_data)
                print(f"\nSaved frame to: {output_file}")
                print("You can view this with a JPEG 2000 viewer or convert with:")
                print(f"  opj_decompress -i {output_file} -o output.png")
                
            break
        break

if __name__ == '__main__':
    main()
