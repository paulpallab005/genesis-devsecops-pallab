# Prod Environment Configuration
# This file defines common settings and prod-specific values

# Configure remote state backend
remote_state {
  backend = "s3"
  
  config = {
    bucket         = "genesis-terraform-state-${get_aws_account_id()}"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "genesis-terraform-locks"
    
    # S3 bucket security settings
    s3_bucket_tags = {
      Name        = "genesis-terraform-state"
      Environment = "shared"
      ManagedBy   = "terragrunt"
      Project     = "genesis-api"
      Owner       = "pallab"
    }
    
    dynamodb_table_tags = {
      Name        = "genesis-terraform-locks"
      Environment = "shared"
      ManagedBy   = "terragrunt"
      Project     = "genesis-api"
      Owner       = "pallab"
    }
  }
  
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}

# Generate provider configuration
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  
  contents = <<EOF
terraform {
  required_version = ">= 1.5.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      ManagedBy   = "terragrunt"
      Project     = "genesis-api"
      Owner       = "pallab"
      Environment = var.environment
    }
  }
}
EOF
}

# Common and environment-specific inputs
inputs = {
  aws_region = "us-east-1"
  project    = "genesis-api"
  owner      = "pallab"
  environment = "prod"
  
  # GitHub configuration for OIDC
  github_org    = "pallab_paul"  # Replace with your GitHub username/org
  github_repo   = "genesis-devsecops-pallab"
  github_branch = "main"  # Or "production" for prod-only deployments
  
  # Alerting configuration
  sns_email_endpoint = "ops-team@example.com"  # Production ops email
  
  # Lambda configuration (prod has higher limits)
  lambda_memory_size = 1024  # More memory for production
  lambda_timeout     = 60    # Longer timeout
  image_tag          = "latest"
  
  # Monitoring thresholds (stricter in prod)
  error_rate_threshold         = 5   # 5% error rate threshold
  error_rate_evaluation_periods = 2  # 2 consecutive periods
}
