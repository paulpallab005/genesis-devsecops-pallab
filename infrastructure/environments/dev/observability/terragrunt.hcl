# Observability Module Configuration for Dev Environment

include "env" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

terraform {
  source = "../../../modules//observability"
}

# Dependency on Compute module
dependency "compute" {
  config_path = "../compute"
  skip_outputs = true
  
  mock_outputs = {
    lambda_function_name = "mock-lambda-function"
    lambda_function_arn  = "arn:aws:lambda:us-east-1:123456789012:function:mock-function"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "apply"]
}

inputs = {
  lambda_function_name = try(dependency.compute.outputs.lambda_function_name, "mock-lambda-function")
  lambda_function_arn  = try(dependency.compute.outputs.lambda_function_arn, "arn:aws:lambda:us-east-1:123456789012:function:mock-function")
}
