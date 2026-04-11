# IAM Module Configuration for Dev Environment

include "env" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

terraform {
  source = "../../../modules//iam"
}

inputs = {}
