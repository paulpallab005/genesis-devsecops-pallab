# Observability Module

This module provisions comprehensive monitoring and alerting for the Genesis Events API using CloudWatch dashboards, metric alarms, and SNS notifications.

## Purpose

Creates production-grade observability infrastructure:
1. **CloudWatch Dashboard**: 7 widgets showing key Lambda metrics and custom application metrics
2. **CloudWatch Alarms**: Error rate threshold and P99 latency anomaly detection
3. **SNS Topic**: Email notifications when alarms trigger or resolve  
4. **Operational Context**: Detailed alarm descriptions with runbook links

## Features

- **Complete Dashboard**: 6 required + 1 custom metric panels
- **Relative Thresholds**: Anomaly detection using metric math (not just static limits)
- **Operational Runbooks**: Alarm descriptions include troubleshooting steps
- **Email Notifications**: SNS delivers alerts on alarm state changes
- **Metric Math**: Calculated metrics like error rate percentage
- **Custom Metrics**: Application-emitted CloudWatch metrics (events by type)

## Usage

```hcl
module "observability" {
  source = "../../modules/observability"
  
  aws_region         = "us-east-1"
  environment        = "dev"
  project            = "genesis-api"
  owner              = "pallab"
  
  # Dependencies: Compute module outputs
  lambda_function_name = module.compute.lambda_function_name
  lambda_function_arn  = module.compute.lambda_function_arn
  
  # Alerting configuration
  sns_email_endpoint           = "ops-team@example.com"
  error_rate_threshold         = 5    # Trigger alarm at 5% error rate
  error_rate_evaluation_periods = 1   # 1 period (5 min)
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| aws_region | AWS region | string | us-east-1 | no |
| environment | Environment name | string | - | yes |
| project | Project name | string | genesis-api | no |
| owner | Owner name | string | pallab | no |
| lambda_function_name | Lambda function name (from compute) | string | - | yes |
| lambda_function_arn | Lambda function ARN | string | - | yes |
| sns_email_endpoint | Email for alarm notifications | string | - | yes |
| error_rate_threshold | Error rate % threshold (1-100) | number | 5 | no |
| error_rate_evaluation_periods | Consecutive periods for alarm | number | 1 | no |

## Outputs

| Name | Description |
|------|-------------|
| dashboard_name | CloudWatch dashboard name |
| dashboard_arn | CloudWatch dashboard ARN |
| sns_topic_arn | SNS topic ARN for alarms |
| sns_topic_name | SNS topic name |
| error_rate_alarm_name | Error rate alarm name |
| error_rate_alarm_arn | Error rate alarm ARN |
| duration_alarm_name | Duration anomaly alarm name |
| duration_alarm_arn | Duration anomaly alarm ARN |

## CloudWatch Dashboard

### Widget 1: Invocations (Requests/Min)
**Purpose**: Traffic signal - shows request volume over time  
**Metric**: `AWS/Lambda` → `Invocations` (Sum, 1-minute period)  
**Use Case**: Identify traffic patterns, detect traffic spikes/drops

### Widget 2: Error Rate % 
**Purpose**: Most important reliability signal  
**Metric**: Metric math: `(Errors / Invocations) × 100`  
**Use Case**: Monitor SLI for availability SLO (target: <5% error rate)

###Widget 3: Duration P50 (Median Latency)
**Purpose**: Typical user experience latency  
**Metric**: `AWS/Lambda` → `Duration` (P50, 5-minute period)  
**Use Case**: Baseline performance monitoring

### Widget 4: Duration P99 (99th Percentile)
**Purpose**: Worst-case user experience (tail latency)  
**Metric**: `AWS/Lambda` → `Duration` (P99, 5-minute period)  
**Use Case**: Detect latency anomalies, set P99 SLO targets

### Widget 5: Throttle Count
**Purpose**: Free tier canary - Lambda invocation limits  
**Metric**: `AWS/Lambda` → `Throttles` (Sum, 5-minute period)  
**Use Case**: Early warning of rate limit exhaustion

### Widget 6: Concurrent Executions
**Purpose**: Scaling behavior visibility  
**Metric**: `AWS/Lambda` → `ConcurrentExecutions` (Maximum, 1-minute period)  
**Use Case**: Understand concurrency patterns, reserved capacity usage

### Widget 7: Custom Metric - Events Created
**Purpose**: Application-level metric from FastAPI  
**Metric**: `GenesisAPI` → `EventsCreated` (Sum, 5-minute period)  
**Dimensions**: `EventType` (user_signup, payment, etc.)  
**Use Case**: Business metrics, feature usage tracking

## CloudWatch Alarms

### Alarm 1: High Error Rate

**Trigger Condition**: Error rate > 5% for 1 consecutive 5-minute period  
**Calculation**: `(Errors / Invocations) × 100 > 5`  
**Notification**: SNS email when alarm triggers or resolves  

**Alarm Description Includes**:
- What the metric measures (error rate percentage)
- What a breach means operationally (app errors, dependency failures)
- Troubleshooting steps (check logs, review deployments, check dependencies)
- SLA (acknowledge in 15 min, resolve in 60 min)
- Runbook URL for detailed procedures

**Why This Matters**: Static threshold alarm that catches systemic errors. If >5% of requests fail, the API is degraded and users are impacted.

### Alarm 2: Duration Anomaly (P99)

**Trigger Condition**: P99 duration exceeds 3× the 7-day rolling baseline for 2 consecutive periods  
**Calculation**: Anomaly detection band with 3 standard deviations  
**Notification**: SNS email when anomaly detected  

**Alarm Description Includes**:
- What is being measured (latency anomaly vs historical baseline)
- Potential causes (cold starts, memory pressure, downstream slowdown)
- Investigation steps (check concurrent executions, review trends, check deployments)
- Mitigation options (increase Lambda memory if sustained high P99)
- Runbook URL

**Why This Matters**: Relative threshold (3× baseline) is better than absolute threshold (e.g., "P99 > 1000ms") because it adapts to normal variance and catches degradation early, even if absolute latency is still acceptable.

## SNS Topic Configuration

- **Encryption**: Uses AWS-managed KMS key (`alias/aws/sns`)
- **Subscription**: Email endpoint (requires confirmation after deployment)
- **Actions**: Receives notifications on both ALARM and OK state changes
- **Display Name**: Human-friendly topic name visible in email subject

**Important**: After first deploy, subscriber must confirm email subscription via confirmation link.

## Metric Math Examples

### Error Rate Calculation
```
error_rate = (m1 / m2) * 100
where:
  m1 = AWS/Lambda.Errors (Sum over 5 min)
  m2 = AWS/Lambda.Invocations (Sum over 5 min)
```

### Anomaly Detection Band
```
ANOMALY_DETECTION_BAND(duration_p99, 3)
```
Creates upper/lower thresholds based on:
- 7-day rolling baseline
- 3 standard deviations from mean
- Alarm triggers when metric exceeds band

## Custom Metrics Integration

Application emits custom metrics via `cloudwatch.put_metric_data`:

```python
import boto3

cloudwatch = boto3.client('cloudwatch')

cloudwatch.put_metric_data(
    Namespace='GenesisAPI',
    MetricData=[{
        'MetricName': 'EventsCreated',
        'Value': 1.0,
        'Unit': 'Count',
        'Dimensions': [
            {'Name': 'EventType', 'Value': 'user_signup'}
        ]
    }]
)
```

This metric appears in Widget 7 of the dashboard.

## Accessing the Dashboard

1. **AWS Console**:
```
CloudWatch → Dashboards → genesis-api-dev-dashboard
```

2. **Direct URL**:
```
https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:name=genesis-api-dev-dashboard
```

3. **AWS CLI**:
```bash
aws cloudwatch get-dashboard --dashboard-name genesis-api-dev-dashboard
```

## Testing Alarms

### Force Error Rate Alarm

Temporarily introduce errors in Lambda:
```python
# In app/main.py
@app.get("/health")
async def health_check():
    import random
    if random.random() < 0.1:  # 10% error rate
        raise Exception("Forced error for alarm testing")
    return {"status": "ok"}
```

Send traffic, wait 5-10 minutes, verify alarm triggers.

### Force Duration Anomaly

Introduce artificial delay:
```python
import time
@app.get("/health"):
    time.sleep(2)  # Add 2-second delay
    return {"status": "ok"}
```

Send sustained traffic, wait for anomaly detection band recalculation.

## Dependencies

**Required Modules:**
- `compute` module (provides `lambda_function_name`, `lambda_function_arn`)

## Resources Created

- 1x CloudWatch Dashboard (7 widgets)
- 2x CloudWatch Metric Alarms
- 1x SNS Topic
- 1x SNS Topic Subscription (email)

## Tags

All resources tagged with:
- **Name**: Resource-specific identifier
- **Environment**: dev/prod/staging
- **Project**: genesis-api
- **ManagedBy**: terragrunt
- **Owner**: Team/person responsible

## Checkov Compliance

- ✅ SNS topic encrypted with KMS
- ✅ CloudWatch alarms have actions configured
- ✅ All resources tagged
- ⚠️ Dashboard has no encryption (not applicable - dashboard data is not sensitive)

---

**Module Version**: 1.0.0  
**Last Updated**: April 11, 2026  
**Maintained By**: Pallab Paul
