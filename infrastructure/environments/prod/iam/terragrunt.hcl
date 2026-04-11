# IAM Module Configuration for Prod Environment

include "env" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

terraform {
  source = "../../../modules//iam"
}

inputs = {}
