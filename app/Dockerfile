# Multi-stage Dockerfile for Genesis Events API
# Stage 1: Builder - Install dependencies and compile
# Stage 2: Runtime - Minimal image with only necessary files

# ============================================
# Stage 1: Builder
# ============================================
FROM python:3.11-slim AS builder
WORKDIR /build
RUN apt-get update && apt-get install -y --no-install-recommends gcc g++ && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir --prefix=/install -r requirements.txt

# Stage 2: Runtime
FROM python:3.11-slim
WORKDIR /app

# 1. ADD THE LAMBDA ADAPTER
# This binary translates Lambda events into HTTP requests for your FastAPI app
COPY --from=public.ecr.aws/awsguru/aws-lambda-adapter:0.8.4 /lambda-adapter /opt/extensions/lambda-adapter

# Create non-root user
RUN groupadd -r appuser && useradd -r -g appuser -d /app -s /sbin/nologin appuser

# Copy installed packages and code
COPY --from=builder /install /usr/local
COPY main.py .

# 2. ENSURE PERMISSIONS
# The adapter needs to run in /opt/extensions, and the app in /app
RUN chown -R appuser:appuser /app
USER appuser

# Set environment variables for the adapter
ENV PORT=8080 \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    ENVIRONMENT=dev

EXPOSE 8080

# Run the application using uvicorn directly
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]