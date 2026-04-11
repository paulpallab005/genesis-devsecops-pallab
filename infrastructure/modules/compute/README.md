# Compute Module

This module provisions the serverless compute infrastructure for the Genesis Events API using AWS Lambda with container images stored in ECR.

## Purpose

Creates serverless compute resources:
1. **ECR Repository**: Stores container images with scanning and lifecycle policies
2. **Lambda Function**: Runs the FastAPI application from ECR image
3. **Lambda Function URL**: Provides HTTP access without API Gateway
4. **CloudWatch Log Group**: Centralized logging with configurable retention

## Features

- **Container-Based Lambda**: Uses ECR images for consistent deploys
- **Image Scanning**: ECR scans images on push for vulnerabilities
- **Lifecycle Management**: Automatically removes old images (keeps last 10)
- **Function URL**: Direct HTTP access with CORS configuration
- **Concurrency Limits**: Prevents runaway costs with reserved concurrency
- **Log Retention**: Environment-specific retention (7 days dev, 30 days prod)

## Usage

```hcl
module "compute" {
  source = "../../modules/compute"
  
  aws_region                = "us-east-1"
  environment               = "dev"
  project                   = "genesis-api"
  owner                     = "pallab"
  
  # Dependency: IAM module output
  lambda_execution_role_arn = module.iam.lambda_execution_role_arn
  
  lambda_memory_size        = 512
  lambda_timeout            = 30
  image_tag                 = "latest"
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| aws_region | AWS region for resources | string | us-east-1 | no |
| environment | Environment name | string | - | yes |
| project | Project name | string | genesis-api | no |
| owner | Owner/team name | string | pallab | no |
| lambda_execution_role_arn | IAM role ARN for Lambda | string | - | yes |
| lambda_memory_size | Memory in MB (128-10240) | number | 512 | no |
| lambda_timeout | Timeout in seconds (1-900) | number | 30 | no |
| image_tag | Docker image tag | string | latest | no |
| log_retention_days | Log retention period | number | 7 | no |

## Outputs

| Name | Description |
|------|-------------|
| ecr_repository_url | ECR repository URL for docker push |
| ecr_repository_name | ECR repository name |
| ecr_repository_arn | ECR repository ARN |
| lambda_function_arn | Lambda function ARN (for observability module) |
| lambda_function_name | Lambda function name |
| lambda_function_url | Public HTTP URL for API access |
| lambda_log_group_name | CloudWatch log group name |
| lambda_log_group_arn | CloudWatch log group ARN |

## Architecture

```
GitHub Actions (OIDC)
  │
  ├─> Build Docker Image
  │
  ├─> Push to ECR  ──> ECR Repository
  │                      │ 
  │                      ├─> Image Scanning (Trivy/ECR)
  │                      ├─> Lifecycle Policy (keep 10)
  │                      └─> Encryption (AES256)
  │
  └─> Update Lambda ──> Lambda Function
                          │
                          ├─> Execution Role (IAM)
                          ├─> Function URL (HTTP)
                          ├─> Environment Variables
                          └─> CloudWatch Logs
```

## Image Deployment

### Initial Deployment

1. Build and push initial image:
```bash
# Authenticate to ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com

# Build image
docker build -t genesis-api:latest ./app

# Tag for ECR
docker tag genesis-api:latest ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/genesis-api-dev:latest

# Push to ECR
docker push ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/genesis-api-dev:latest
```

2. Deploy Lambda (Terragrunt will create function with placeholder image):
```bash
terragrunt apply
```

### Updates (CI/CD Pipeline)

GitHub Actions updates Lambda code without Terraform:
```bash
aws lambda update-function-code \
  --function-name genesis-api-dev-api \
  --image-uri ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/genesis-api-dev:SHA
```

## Lambda Configuration

### Environment Variables

- **ENVIRONMENT**: Current environment (dev/prod)
- **AWS_REGION**: AWS region
- **LOG_LEVEL**: Logging verbosity (DEBUG for dev, INFO for prod)

### Resource Limits

- **Memory**: 512 MB default (configurable 128-10240 MB)
- **Timeout**: 30 seconds default (configurable 1-900 seconds)
- **Reserved Concurrency**: 5 (dev), 10 (prod) - prevents cost overruns

### Security

- **Function URL**: Currently NONE auth (add AWS_IAM for production)
- **CORS**: Wide-open for dev (* origins) - restrict for production
- **Log Group**: Explicit creation ensures consistent permissions

## Monitoring Integration

Lambda metrics automatically available:
- **Invocations**: Count of function calls
- **Errors**: Count of failed executions
- **Duration**: Execution time per invocation
- **Throttles**: Count of rate-limited requests
- **ConcurrentExecutions**: Number of simultaneous executions

Use these metrics in the `observability` module for dashboards and alarms.

## Cost Optimization

- **Lifecycle Policy**: Removes old images to minimize ECR storage costs
- **Reserved Concurrency**: Caps concurrent executions to prevent bill shock
- **Log Retention**: Shorter retention in dev (7 days vs 30 days prod)
- **Lambda Sizing**: 512 MB for API workload, increase if P99 latency high

## Dependencies

**Required Modules:**
- `iam` module (provides `lambda_execution_role_arn`)

**Consumed By:**
- `observability` module (uses Lambda ARN/name for monitoring)

## Resources Created

- 1x ECR Repository
- 1x ECR Lifecycle Policy
- 1x Lambda Function
- 1x Lambda Function URL
- 1x CloudWatch Log Group

## Tags

All resources tagged with:
- **Name**: Resource-specific identifier
- **Environment**: dev/prod/staging
- **Project**: genesis-api
- **ManagedBy**: terragrunt
- **Owner**: Team/person responsible

## Checkov Compliance

- ✅ ECR encryption enabled (AES256)
- ✅ ECR image scanning enabled
- ✅ Lambda has reserved concurrent executions (cost control)
- ✅ CloudWatch log retention configured
- ✅ All resources tagged

---

**Module Version**: 1.0.0  
**Last Updated**: April 11, 2026  
**Maintained By**: Pallab Paul
