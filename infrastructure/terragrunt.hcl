# Root terragrunt.hcl

locals {
  # Load environment-level variables
  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  
  # Extract out common variables for reuse
  project     = "genesis-api"
  environment = local.env_vars.locals.environment
  aws_region  = local.env_vars.locals.aws_region
}

# Generate an AWS provider block
# This prevents the "Duplicate required providers" error by centralizing the config
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region = "${local.aws_region}"

  default_tags {
    tags = {
      Project     = "${local.project}"
      Environment = "${local.environment}"
      ManagedBy   = "terragrunt"
    }
  }
}
EOF
}

# Generate a versions block to satisfy TFLint version constraints
generate "versions" {
  path      = "versions.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
EOF
}

# Configure Terragrunt to automatically store tfstate in S3
remote_state {
  backend = "s3"
  config = {
    encrypt        = true
    bucket         = "genesis-terraform-state-${get_aws_account_id()}"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = local.aws_region
    dynamodb_table = "genesis-terraform-locks"
  }
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
}

# Combine all variables to be passed to all modules
inputs = merge(
  local.env_vars.locals,
  {
    project = local.project
  }
)