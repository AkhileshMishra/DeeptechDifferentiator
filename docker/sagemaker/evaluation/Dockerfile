# Healthcare Imaging MLOps Platform - Evaluation Container
FROM python:3.11-slim

LABEL maintainer="Cloud Assembly"
LABEL description="Model evaluation container for SageMaker"

# Set environment variables
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# Create working directory
WORKDIR /opt/ml/code

# Copy requirements and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy source code
COPY evaluate.py .

# Set entrypoint
ENTRYPOINT ["python", "evaluate.py"]
