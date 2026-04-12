# Compute Module Variables

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
  
}

variable "environment" {
  description = "Environment name (dev, prod, staging)"
  type        = string
  
  validation {
    condition     = contains(["dev", "prod", "staging"], var.environment)
    error_message = "Environment must be dev, prod, or staging."
  }
}

variable "project" {
  description = "Project name used for resource naming"
  type        = string
  default     = "genesis-api"
}

variable "owner" {
  description = "Owner or team responsible for these resources"
  type        = string
  default     = "pallab"
}

variable "lambda_execution_role_arn" {
  description = "ARN of the IAM role for Lambda execution (from IAM module)"
  type        = string
}

variable "lambda_memory_size" {
  description = "Amount of memory in MB allocated to Lambda function"
  type        = number
  default     = 512
  
  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory must be between 128 and 10240 MB."
  }
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 30
  
  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "image_tag" {
  description = "Docker image tag to deploy to Lambda"
  type        = string
  default     = "latest"
}

