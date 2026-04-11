# Observability Module Outputs

output "dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.api.dashboard_name
}

output "dashboard_arn" {
  description = "ARN of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.api.dashboard_arn
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alarm notifications"
  value       = aws_sns_topic.alarms.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic"
  value       = aws_sns_topic.alarms.name
}

output "error_rate_alarm_name" {
  description = "Name of the error rate CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.error_rate.alarm_name
}

output "error_rate_alarm_arn" {
  description = "ARN of the error rate alarm"
  value       = aws_cloudwatch_metric_alarm.error_rate.arn
}

output "duration_alarm_name" {
  description = "Name of the duration anomaly CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.duration_anomaly.alarm_name
}

output "duration_alarm_arn" {
  description = "ARN of the duration anomaly alarm"
  value       = aws_cloudwatch_metric_alarm.duration_anomaly.arn
}
