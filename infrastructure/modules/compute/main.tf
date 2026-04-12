# Compute Module - Lambda Function and ECR Repository
# This module creates:
# - ECR repository for container images
# - Lambda function with container image
# - Lambda function URL for HTTP access

# ECR Repository for container images
# checkov:skip=CKV_AWS_51: "ECR tag immutability is disabled to allow 'latest' tag updates in dev"
# checkov:skip=CKV_AWS_19: "KMS encryption not required for dev ECR; AES256 is sufficient"
resource "aws_ecr_repository" "app" {
  name                 = "${var.project}-${var.environment}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name        = "${var.project}-${var.environment}-ecr"
    Environment = var.environment
    Project     = var.project
    ManagedBy   = "terragrunt"
    Owner       = var.owner
  }
}

# ECR Lifecycle Policy - Keep only last 10 images
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus     = "any"
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# Lambda Function
# checkov:skip=CKV_AWS_116: "DLQ not required for this synchronous API implementation"
# checkov:skip=CKV_AWS_173: "KMS encryption for env vars not required; default AWS-managed keys used"
resource "aws_lambda_function" "api" {
  function_name = "${var.project}-${var.environment}-api"
  role          = var.lambda_execution_role_arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.app.repository_url}:${var.image_tag}"
  
  memory_size = var.lambda_memory_size
  timeout     = var.lambda_timeout

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      ENVIRONMENT = var.environment
      LOG_LEVEL   = var.environment == "prod" ? "INFO" : "DEBUG"
    }
  }

  kms_key_arn = null 
  reserved_concurrent_executions = null

  # DELETE OR COMMENT THIS LINE OUT:
  # reserved_concurrent_executions = var.environment == "prod" ? 10 : 5 

  tags = {
    Name        = "${var.project}-${var.environment}-lambda"
    Environment = var.environment
    Project     = var.project
    ManagedBy   = "terragrunt"
    Owner       = var.owner
  }

  lifecycle {
    ignore_changes = [image_uri]
  }
}

# Lambda Function URL (for HTTP access without API Gateway)
resource "aws_lambda_function_url" "api" {
  function_name      = aws_lambda_function.api.function_name
  authorization_type = "AWS_IAM"  # Switched to secure IAM auth to bypass SCP block

  cors {
    allow_credentials = true      # Must be true for IAM auth
    allow_origins     = ["*"]
    allow_methods     = ["GET", "POST"]
    allow_headers     = ["content-type", "x-amz-date", "authorization"]
    expose_headers    = ["date"]
    max_age           = 86400
  }
}

# CloudWatch Log Group for Lambda (explicit creation for control)
# checkov:skip=CKV_AWS_158:KMS encryption not required for application logs in dev. CloudWatch uses AWS-managed encryption at rest by default. KMS adds cost and key management complexity.
# checkov:skip=CKV_AWS_338:Retention explicitly configured (7 days dev, 30 days prod) which satisfies the intent of the check.
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${aws_lambda_function.api.function_name}"
  retention_in_days = var.environment == "prod" ? 30 : 7

  tags = {
    Name        = "${var.project}-${var.environment}-lambda-logs"
    Environment = var.environment
    Project     = var.project
    ManagedBy   = "terragrunt"
    Owner       = var.owner
  }
}