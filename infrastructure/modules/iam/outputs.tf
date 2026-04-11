# IAM Module Outputs

output "github_actions_role_arn" {
  description = "ARN of the IAM role for GitHub Actions to assume via OIDC"
  value       = aws_iam_role.github_actions_role.arn
}

output "github_actions_role_name" {
  description = "Name of the GitHub Actions deployment role"
  value       = aws_iam_role.github_actions_role.name
}

output "lambda_execution_role_arn" {
  description = "ARN of the Lambda execution role with least-privilege permissions"
  value       = aws_iam_role.lambda_execution_role.arn
}

output "lambda_execution_role_name" {
  description = "Name of the Lambda execution role"
  value       = aws_iam_role.lambda_execution_role.name
}

output "oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC identity provider"
  value       = aws_iam_openid_connect_provider.github_actions.arn
}

output "oidc_provider_url" {
  description = "URL of the OIDC provider"
  value       = aws_iam_openid_connect_provider.github_actions.url
}
