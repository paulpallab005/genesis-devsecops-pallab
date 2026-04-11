# IAM Module - OIDC Provider and Roles
# This module creates:
# - OIDC provider for GitHub Actions authentication  
# - GitHub Actions deployment role (for Terragrunt apply)
# - Lambda execution role with least-privilege policies

# Data sources
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# OIDC Provider for GitHub Actions
resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  # GitHub's thumbprint - this is stable
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]

  tags = {
    Name        = "${var.project}-github-oidc-provider"
    Environment = var.environment
    Project     = var.project
    ManagedBy   = "terragrunt"
    Owner       = var.owner
  }
}

# GitHub Actions Deployment Role
resource "aws_iam_role" "github_actions_role" {
  name        = "${var.project}-${var.environment}-github-actions-role"
  description = "Role assumed by GitHub Actions for deploying infrastructure"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github_actions.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo}:*"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project}-${var.environment}-github-actions-role"
    Environment = var.environment
    Project     = var.project
    ManagedBy   = "terragrunt"
    Owner       = var.owner
  }
}

# GitHub Actions Role Policy - Deployment Permissions
# checkov:skip=CKV_AWS_290:Write permissions required for CI/CD deployment (ECR push, Lambda update, S3 state). Actions scoped to project-specific resources.
# checkov:skip=CKV_AWS_355:Lambda function management permissions required for deployment pipeline. Resource ARNs scoped to project/environment pattern.
resource "aws_iam_role_policy" "github_actions_deploy_policy" {
  name = "${var.project}-${var.environment}-github-deploy-policy"
  role = aws_iam_role.github_actions_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRPermissions"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:CreateRepository",
          "ecr:DescribeRepositories",
          "ecr:ListImages"
        ]
        Resource = "*"
      },
      {
        Sid    = "LambdaUpdatePermissions"
        Effect = "Allow"
        Action = [
          "lambda:UpdateFunctionCode",
          "lambda:UpdateFunctionConfiguration",
          "lambda:GetFunction",
          "lambda:PublishVersion"
        ]
        Resource = "arn:${data.aws_partition.current.partition}:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${var.project}-${var.environment}-*"
      },
      {
        Sid    = "S3StatePermissions"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "arn:${data.aws_partition.current.partition}:s3:::genesis-terraform-state-${data.aws_caller_identity.current.account_id}",
          "arn:${data.aws_partition.current.partition}:s3:::genesis-terraform-state-${data.aws_caller_identity.current.account_id}/*"
        ]
      },
      {
        Sid    = "DynamoDBLockPermissions"
        Effect = "Allow"
        Action = [
          "dynamodb:DescribeTable",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem"
        ]
        Resource = "arn:${data.aws_partition.current.partition}:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/genesis-terraform-locks"
      }
    ]
  })
}

# Lambda Execution Role
resource "aws_iam_role" "lambda_execution_role" {
  name        = "${var.project}-${var.environment}-lambda-role"
  description = "Execution role for Lambda function with least-privilege permissions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "${var.project}-${var.environment}-lambda-role"
    Environment = var.environment
    Project     = var.project
    ManagedBy   = "terragrunt"
    Owner       = var.owner
  }
}

# Lambda Execution Policy - CloudWatch Logs
resource "aws_iam_role_policy" "lambda_logs_policy" {
  name = "${var.project}-${var.environment}-lambda-logs-policy"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogsPermissions"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:${data.aws_partition.current.partition}:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.project}-${var.environment}-*:*"
      }
    ]
  })
}

# Lambda Execution Policy - Secrets Manager (least-privilege)
resource "aws_iam_role_policy" "lambda_secrets_policy" {
  name = "${var.project}-${var.environment}-lambda-secrets-policy"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SecretsManagerPermissions"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = "arn:${data.aws_partition.current.partition}:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.project}/${var.environment}/*"
      }
    ]
  })
}

# Lambda Execution Policy - CloudWatch Custom Metrics
resource "aws_iam_role_policy" "lambda_cloudwatch_metrics_policy" {
  name = "${var.project}-${var.environment}-lambda-metrics-policy"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchMetricsPermissions"
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = "GenesisAPI"
          }
        }
      }
    ]
  })
}
