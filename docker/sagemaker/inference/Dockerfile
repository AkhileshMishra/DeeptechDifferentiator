# Healthcare Imaging MLOps Platform - Inference Container
FROM tensorflow/tensorflow:2.13.0

LABEL maintainer="Cloud Assembly"
LABEL description="Model inference container for SageMaker"

# Set environment variables
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    nginx \
    && rm -rf /var/lib/apt/lists/*

# Create working directory
WORKDIR /opt/ml/code

# Copy requirements and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy source code
COPY predictor.py .
COPY serve .

# Make serve script executable
RUN chmod +x serve

# Set entrypoint for SageMaker
ENV SAGEMAKER_PROGRAM predictor.py

ENTRYPOINT ["python", "predictor.py"]
