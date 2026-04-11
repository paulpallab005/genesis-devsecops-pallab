# Prod Environment Configuration
# Inherits from root terragrunt.hcl and adds prod-specific values

include "root" {
  path = find_in_parent_folders()
}

# Production-specific inputs
inputs = {
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
