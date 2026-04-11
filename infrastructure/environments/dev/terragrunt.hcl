# Dev Environment Configuration
# This file defines common settings and dev-specific values

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
  environment = "dev"
  
  # GitHub configuration for OIDC
  github_org    = "paulpallab005"  # Replace with your GitHub username/org
  github_repo   = "genesis-devsecops-pallab"
  github_branch = "main"
  
  # Alerting configuration
  sns_email_endpoint = "pallab.paul@example.com"  # Replace with your email
  
  # Lambda configuration (dev has lower limits)
  lambda_memory_size = 512
  lambda_timeout     = 30
  image_tag          = "latest"
  
  # Monitoring thresholds (more relaxed in dev)
  error_rate_threshold         = 10  # 10% error rate threshold
  error_rate_evaluation_periods = 1
}
