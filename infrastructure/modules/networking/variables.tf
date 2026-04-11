# Networking Module Variables

variable "aws_region" {
  description = "AWS region for network resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (dev, prod, staging)"
  type        = string
}

variable "project" {
  description = "Project name"
  type        = string
  default     = "genesis-api"
}

variable "owner" {
  description = "Owner or team name"
  type        = string
  default     = "pallab"
}
