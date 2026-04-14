# .tflint.hcl

config {
  module = true
  force = false
}

# Disable version requirement rules that Terragrunt handles externally
rule "terraform_required_version" {
  enabled = false
}

rule "terraform_required_providers" {
  enabled = false
}

# Ensure other best practices remain active
rule "terraform_unused_declarations" {
  enabled = true
}

rule "terraform_deprecated_interpolation" {
  enabled = true
}