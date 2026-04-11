# Dev Environment Configuration
# Inherits from root terragrunt.hcl and adds dev-specific values

include "root" {
  path = find_in_parent_folders()
}

# Environment-specific inputs
inputs = {
  environment = "dev"
  
  # GitHub configuration for OIDC
  github_org    = "pallab_paul"  # Replace with your GitHub username/org
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
