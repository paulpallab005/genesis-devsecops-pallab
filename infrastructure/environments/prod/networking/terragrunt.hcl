# Networking Module Configuration for Prod Environment

include "root" {
  path = find_in_parent_folders()
}

include "env" {
  path   = find_in_parent_folders("terragrunt.hcl")
  expose = true
}

terraform {
  source = "../../modules//networking"
}

inputs = {}
