# Observability Module - CloudWatch Dashboard, Alarms, and SNS
# This module creates comprehensive monitoring for the Lambda function:
# - CloudWatch Dashboard with 6+ required panels
# - CloudWatch Alarms (error rate, duration anomaly)
# - SNS topic for alarm notifications

# SNS Topic for Alarms
resource "aws_sns_topic" "alarms" {
  name              = "${var.project}-${var.environment}-alarms"
  display_name      = "Genesis API ${var.environment} Alarms"
  kms_master_key_id = "alias/aws/sns"  # Encrypt with AWS managed key

  tags = {
    Name        = "${var.project}-${var.environment}-sns-alarms"
    Environment = var.environment
    Project     = var.project
    ManagedBy   = "terragrunt"
    Owner       = var.owner
  }
}

# SNS Topic Subscription
resource "aws_sns_topic_subscription" "alarm_email" {
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.sns_email_endpoint
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "api" {
  dashboard_name = "${var.project}-${var.environment}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      # Widget 1: Invocations (requests/min)
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/Lambda", "Invocations", { stat = "Sum", label = "Invocations" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "Lambda Invocations (requests/min)"
          period  = 60
          yAxis = {
            left = {
              label = "Count"
            }
          }
        }
        width  = 12
        height = 6
        x      = 0
        y      = 0
      },
      
      # Widget 2: Error Rate % (Errors / Invocations × 100)
      {
        type = "metric"
        properties = {
          metrics = [
            [{ expression = "(m1/m2)*100", label = "Error Rate %", id = "e1" }],
            ["AWS/Lambda", "Errors", { stat = "Sum", id = "m1", visible = false }],
            ["AWS/Lambda", "Invocations", { stat = "Sum", id = "m2", visible = false }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "Error Rate % (Errors/Invocations × 100)"
          period  = 300
          yAxis = {
            left = {
              label = "Percentage"
              min   = 0
              max   = 100
            }
          }
        }
        width  = 12
        height = 6
        x      = 12
        y      = 0
      },
      
      # Widget 3: Duration P50 (median latency)
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/Lambda", "Duration", { stat = "p50", label = "P50 Latency" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "Duration P50 (Median Latency)"
          period  = 300
          yAxis = {
            left = {
              label = "Milliseconds"
            }
          }
        }
        width  = 8
        height = 6
        x      = 0
        y      = 6
      },
      
      # Widget 4: Duration P99 (99th percentile latency)
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/Lambda", "Duration", { stat = "p99", label = "P99 Latency" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "Duration P99 (99th Percentile)"
          period  = 300
          yAxis = {
            left = {
              label = "Milliseconds"
            }
          }
        }
        width  = 8
        height = 6
        x      = 8
        y      = 6
      },
      
      # Widget 5: Throttle Count
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/Lambda", "Throttles", { stat = "Sum", label = "Throttles" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "Throttle Count (Free Tier Canary)"
          period  = 300
          yAxis = {
            left = {
              label = "Count"
            }
          }
        }
        width  = 8
        height = 6
        x      = 16
        y      = 6
      },
      
      # Widget 6: Concurrent Executions
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/Lambda", "ConcurrentExecutions", { stat = "Maximum", label = "Concurrent Executions" }]
          }
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "Concurrent Executions (Scaling Behavior)"
          period  = 60
          yAxis = {
            left = {
              label = "Count"
            }
          }
        }
        width  = 12
        height = 6
        x      = 0
        y      = 12
      },
      
      # Widget 7: Custom Metric - Events by Type
      {
        type = "metric"
        properties = {
          metrics = [
            ["GenesisAPI", "EventsCreated", { stat = "Sum", label = "Events Created" }]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.aws_region
          title   = "Custom Metric: Events Created by Type"
          period  = 300
          yAxis = {
            left = {
              label = "Count"
            }
          }
        }
        width  = 12
        height = 6
        x      = 12
        y      = 12
      }
    ]
  })
}

# Alarm 1: Error Rate > 5% over 5 minutes
resource "aws_cloudwatch_metric_alarm" "error_rate" {
  alarm_name          = "${var.project}-${var.environment}-high-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.error_rate_evaluation_periods
  threshold           = var.error_rate_threshold
  treat_missing_data  = "notBreaching"
  
  alarm_description = <<-EOT
    OPERATIONAL CONTEXT:
    This alarm monitors the error rate of the ${var.project} API in ${var.environment}.
    
    WHAT THIS MEASURES:
    Percentage of failed Lambda invocations: (Errors / Invocations) × 100
    
    WHAT A BREACH MEANS:
    When error rate exceeds ${var.error_rate_threshold}% over a 5-minute window, this indicates:
    - Application code errors (500 responses)
    - Dependency failures (database, external APIs)
    - Resource exhaustion (memory, timeout)
    
    OPERATIONAL RESPONSE:
    1. Check CloudWatch Logs for error messages: /aws/lambda/${var.lambda_function_name}
    2. Review recent deployments (rollback if issue started after deploy)
    3. Check downstream dependencies (Secrets Manager, external services)
    4. If errors persist >15 min, escalate to on-call engineer
    
    RUNBOOK:
    https://github.com/${var.project}/wiki/runbooks/high-error-rate
    
    SLA:
    - Acknowledge: 15 minutes
    - Resolve: 60 minutes (or implement mitigation)
  EOT

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  metric_query {
    id          = "error_rate"
    expression  = "(errors / invocations) * 100"
    label       = "Error Rate %"
    return_data = true
  }

  metric_query {
    id = "errors"
    metric {
      metric_name = "Errors"
      namespace   = "AWS/Lambda"
      period      = 300
      stat        = "Sum"
      dimensions = {
        FunctionName = var.lambda_function_name
      }
    }
  }

  metric_query {
    id = "invocations"
    metric {
      metric_name = "Invocations"
      namespace   = "AWS/Lambda"
      period      = 300
      stat        = "Sum"
      dimensions = {
        FunctionName = var.lambda_function_name
      }
    }
  }

  tags = {
    Name        = "${var.project}-${var.environment}-error-rate-alarm"
    Environment = var.environment
    Project     = var.project
    ManagedBy   = "terragrunt"
    Owner       = var.owner
  }
}

# Alarm 2: Duration Anomaly - P99 > 3x 7-day baseline
resource "aws_cloudwatch_metric_alarm" "duration_anomaly" {
  alarm_name          = "${var.project}-${var.environment}-duration-anomaly"
  comparison_operator = "LessThanLowerOrGreaterThanUpperThreshold"
  evaluation_periods  = 2
  threshold_metric_id = "anomaly_threshold"
  treat_missing_data  = "notBreaching"
  
  alarm_description = <<-EOT
    OPERATIONAL CONTEXT:
    This alarm detects anomalous latency patterns in ${var.environment} by comparing
    current P99 duration against a 7-day rolling baseline.
    
    WHAT THIS MEASURES:
    P99 latency exceeding 3× the 7-day average P99 (anomaly detection)
    
    WHAT A BREACH MEANS:
    Abnormal performance degradation that could indicate:
    - Cold start issues
    - Memory pressure
    - Downstream service slowdown
    - Database query regression
    
    OPERATIONAL RESPONSE:
    1. Check concurrent executions (scaling issues?)
    2. Review P99 trend over last 24h
    3. Compare against deployment timeline
    4. Check CloudWatch Insights for slow queries/operations
    5. If P99 > 3000ms sustained, consider increasing Lambda memory
    
    RUNBOOK:
    https://github.com/${var.project}/wiki/runbooks/latency-anomaly
  EOT

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]

  metric_query {
    id          = "duration_p99"
    return_data = true
    metric {
      metric_name = "Duration"
      namespace   = "AWS/Lambda"
      period      = 300
      stat        = "p99"
      dimensions = {
        FunctionName = var.lambda_function_name
      }
    }
  }

  metric_query {
    id          = "anomaly_threshold"
    expression  = "ANOMALY_DETECTION_BAND(duration_p99, 3)"
    label       = "P99 Duration Anomaly (3 stddev)"
    return_data = true
  }

  tags = {
    Name        = "${var.project}-${var.environment}-duration-alarm"
    Environment = var.environment
    Project     = var.project
    ManagedBy   = "terragrunt"
    Owner       = var.owner
  }
}

