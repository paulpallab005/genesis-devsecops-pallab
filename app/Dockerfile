# Stage 1: Builder
FROM python:3.11-slim-bookworm AS builder
WORKDIR /build

# Patch vulnerabilities in the builder stage
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y --no-install-recommends gcc g++ && \
    rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# Stage 2: Runtime
FROM python:3.11-slim-bookworm
WORKDIR /app

# Crucial: Explicitly patch OS-level vulnerabilities found by Trivy
RUN apt-get update && apt-get upgrade -y && rm -rf /var/lib/apt/lists/*

COPY --from=public.ecr.aws/awsguru/aws-lambda-adapter:0.8.4 /lambda-adapter /opt/extensions/lambda-adapter
COPY --from=builder /install /usr/local
COPY main.py .

ENV PORT=8080
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]