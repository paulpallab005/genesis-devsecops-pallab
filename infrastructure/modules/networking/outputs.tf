# Networking Module Outputs

output "vpc_id" {
  description = "VPC ID (null for default execution environment)"
  value       = null
}

output "private_subnet_ids" {
  description = "List of private subnet IDs for Lambda (empty for default)"
  value       = []
}

output "security_group_id" {
  description = "Security group ID for Lambda (null for default)"
  value       = null
}
