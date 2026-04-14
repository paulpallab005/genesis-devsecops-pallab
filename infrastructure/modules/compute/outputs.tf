# Compute Module Outputs

output "ecr_repository_url" {
  description = "Full URL of the ECR repository (use for docker push)"
  value       = aws_ecr_repository.app.repository_url
}

output "ecr_repository_name" {
  description = "Name of the ECR repository"
  value       = aws_ecr_repository.app.name
}

output "ecr_repository_arn" {
  description = "ARN of the ECR repository"
  value       = aws_ecr_repository.app.arn
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function (use for monitoring module)"
  value       = aws_lambda_function.api.arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.api.function_name
}

output "lambda_function_url" {
  description = "Public HTTP URL for accessing the Lambda function"
  value       = aws_lambda_function_url.api.function_url
}

output "lambda_log_group_name" {
  description = "Name of the CloudWatch log group for Lambda logs"
  value       = aws_cloudwatch_log_group.lambda.name
}

output "lambda_log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.lambda.arn
}