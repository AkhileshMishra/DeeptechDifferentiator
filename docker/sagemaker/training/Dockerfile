# Healthcare Imaging MLOps Platform - Training Container
FROM tensorflow/tensorflow:2.13.0-gpu

LABEL maintainer="Cloud Assembly"
LABEL description="GPU-accelerated training container for pneumonia detection"

# Set environment variables
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    && rm -rf /var/lib/apt/lists/*

# Create working directory
WORKDIR /opt/ml/code

# Copy requirements and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy source code
COPY train.py .

# Set entrypoint
ENTRYPOINT ["python", "train.py"]
