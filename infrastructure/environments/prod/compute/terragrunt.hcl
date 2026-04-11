# Compute Module Configuration for Prod Environment

include "root" {
  path = find_in_parent_folders()
}

include "env" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

terraform {
  source = "../../modules//compute"
}

# Dependency on IAM module
dependency "iam" {
  config_path = "../iam"
  
  mock_outputs = {
    lambda_execution_role_arn = "arn:aws:iam::123456789012:role/mock-lambda-role"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

inputs = {
  lambda_execution_role_arn = dependency.iam.outputs.lambda_execution_role_arn
}
