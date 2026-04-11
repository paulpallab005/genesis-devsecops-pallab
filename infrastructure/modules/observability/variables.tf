# Observability Module Variables

variable "aws_region" {
  description = "AWS region where resources are deployed"
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
  description = "Project name for resource naming"
  type        = string
  default     = "genesis-api"
}

variable "owner" {
  description = "Owner or team responsible for these resources"
  type        = string
  default     = "pallab"
}

variable "lambda_function_name" {
  description = "Name of the Lambda function to monitor (from compute module)"
  type        = string
}

variable "lambda_function_arn" {
  description = "ARN of the Lambda function (from compute module)"
  type        = string
}

variable "sns_email_endpoint" {
  description = "Email address to receive alarm notifications"
  type        = string
  
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.sns_email_endpoint))
    error_message = "Must provide a valid email address."
  }
}

variable "error_rate_threshold" {
  description = "Error rate percentage threshold to trigger alarm (default: 5%)"
  type        = number
  default     = 5
  
  validation {
    condition     = var.error_rate_threshold > 0 && var.error_rate_threshold <= 100
    error_message = "Error rate threshold must be between 1 and 100 percent."
  }
}

variable "error_rate_evaluation_periods" {
  description = "Number of consecutive periods error rate must exceed threshold"
  type        = number
  default     = 1
  
  validation {
    condition     = var.error_rate_evaluation_periods >= 1 && var.error_rate_evaluation_periods <= 5
    error_message = "Evaluation periods must be between 1 and 5."
  }
}
