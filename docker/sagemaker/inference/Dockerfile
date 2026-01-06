# Healthcare Imaging MLOps Platform - Inference Container
FROM python:3.11-slim

LABEL maintainer="Cloud Assembly"
LABEL description="Inference serving container for SageMaker"

# Set environment variables
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Create working directory
WORKDIR /opt/ml/code

# Copy requirements and install dependencies
COPY docker/sagemaker/inference/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy API source code
COPY python/src/api/ ./api/

# Set entrypoint
ENTRYPOINT ["uvicorn", "api.main:app", "--host", "0.0.0.0", "--port", "8080"]
