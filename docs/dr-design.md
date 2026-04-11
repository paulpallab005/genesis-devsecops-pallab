# Disaster Recovery Design - Genesis Events API

## Executive Summary

This document defines the disaster recovery strategy for the Genesis Events API deployed on AWS Lambda. It includes RTO/RPO targets, component-by-component recovery procedures, a numbered CLI runbook, and gap analysis for production readiness.

**Scenario**: AWS us-east-1 region experiences a complete outage. How do we recover?

---

## 1. Current State Inventory

### What Exists in the Deployed Environment

| Component | Location | Data/State | Loss Impact in Regional Failure |
|-----------|----------|------------|--------------------------------|
| **Lambda Function** | us-east-1 | Code: ECR image<br>Config: Terraform state | ✅ **Recoverable** - Redeploy from ECR in failover region |
| **ECR Repository** | us-east-1 | Container images | ❌ **LOST** - No cross-region replication configured |
| **CloudWatch Logs** | us-east-1 | Application logs (last 7-30 days) | ❌ **LOST** - Logs not replicated |
| **CloudWatch Dashboard** | us-east-1 | Dashboard config | ✅ **Recoverable** - Recreate from Terraform |
| **CloudWatch Alarms** | us-east-1 | Alarm definitions | ✅ **Recoverable** - Recreate from Terraform |
| **SNS Topic** | us-east-1 | Topic config + subscriptions | ✅ **Recoverable** - Recreate from Terraform |
| **IAM Roles** | Global (replicated) | Role definitions, policies | ✅ **SURVIVES** - IAM is globally replicated |
| **Terraform State** | S3 us-east-1 | Infrastructure state | ⚠️ **AT RISK** - Single region S3 bucket |
| **DynamoDB Lock Table** | us-east-1 | State locking records | ⚠️ **AT RISK** - Not replicated |
| **Application Data** | In-memory (Lambda) | Event store (ephemeral) | ❌ **LOST** - Stateless design, no persistence |

### What Would Be Lost

**Permanent Loss**:
- Application data (events created via POST /events) - **BY DESIGN** (stateless)
- Historical logs older than last backup (if any)
- CloudWatch custom metrics history

**Temporary Unavailability** (until recovery):
- API service (cannot process new requests)
- Monitoring visibility (no dashboards/alarms in failover region)

---

## 2. RTO and RPO Targets

### Recovery Time Objective (RTO)

**Target**: **4 hours** from detection of regional failure to fully operational in failover region.

**Justification**:
- **Service Classification**: Internal operations tool, not customer-facing SaaS
- **Business Impact**: Platform team can use alternative event tracking methods (manual logs, Slack) for 4 hours
- **SLO Math**: At 99.5% monthly SLO, allowed downtime = 216 minutes (3.6 hours)
  - 4-hour RTO consumes 66% of monthly error budget for single incident
  - Acceptable for rare catastrophic regional failure (once per year expected)
- **Comparison to Industry**:
  - Customer-facing SaaS: RTO typically 15-60 minutes (requires hot standby)
  - Internal tools: RTO typically 2-8 hours (warm standby acceptable)

**RTO Breakdown** (4 hours total):
| Phase | Duration | Activity |
|-------|----------|----------|
| Detection | 15 min | AWS issues Service Health Dashboard alert; on-call confirms outage |
| Decision | 15 min | Incident commander declares DR failover; team assembled |
| Failover Execution | 2 hours | Execute DR runbook (see Section 4) |
| Validation | 1 hour | Smoke tests, monitoring setup, load testing |
| Communication | 30 min | Notify stakeholders, update status page |

### Recovery Point Objective (RPO)

**Target**: **0 minutes** (zero data loss)

**Justification**:
- **Application Design**: Stateless - no persistent data store
- **Event Data**: Stored in-memory only, lost on Lambda termination by design
- **Configuration**: All infrastructure as code in Git (version-controlled)

**What This Means**:
- No "last backup" to restore from
- Every deployment is a clean slate
- Data loss is **not possible** because data is not persisted

**If Application Were Stateful** (future enhancement):
- RPO would be ~5 minutes (DynamoDB global table replication lag)
- Or RPO = 1 hour (S3 cross-region replication batch interval)

### SLO Impact of 4-Hour RTO

**Calculation**:
```
99.5% SLO = 216 minutes allowed downtime per month
4-hour outage = 240 minutes

If regional failure occurs:
- Single incident: Exceeds monthly SLO by 24 minutes (11% over budget)
- Recovery: Team has −24 minutes of buffer for rest of month
```

**Mitigation**:
- Regional failures are "force majeure" - may exclude from SLO per contract
- Or adjust SLO calculation to 99.0% for month where DR triggered

---

## 3. Recovery Strategy (Component-by-Component)

### Lambda Function Code

**Current State**: Container image stored in ECR (us-east-1 only)

**Recovery Mechanism**:
1. Pull latest image from ECR if region still accessible (read-only mode)
2. If ECR inaccessible: Rebuild image from source code in GitHub
3. Push to ECR in failover region (us-west-2)
4. Deploy Lambda in us-west-2 via Terragrunt

**Dependencies**: GitHub repository must be accessible, Docker build tooling available

**Gap**: ❌ **No cross-region ECR replication** - must rebuild or manually replicate before failure

### Terraform State

**Current State**: S3 bucket in us-east-1 (`genesis-terraform-state-{account_id}`)

**Recovery Mechanism**:
- **If bucket has versioning enabled** (it does): Restore from S3 version history once region recovers
- **If region is permanently lost**: Bootstrap new state from actual resources using `terraform import`
- **If cross-region replication configured** (it's not): Failover to replica bucket in us-west-2

**Dependencies**: S3 versioning must be enabled (already configured in terragrunt.hcl)

**Gap**: ❌ **No cross-region replication** - state recovery depends on us-east-1 eventually recovering

### Application Data

**Current State**: Ephemeral, in-memory only

**Recovery Mechanism**: **None - by design**

**Business Impact**: Events created between last manual backup (if any) and failure time are lost

**Mitigation** (if data persistence required in future):
- DynamoDB global tables (RPO ≈ 1 second)
- S3 cross-region replication (RPO ≈ 15 minutes)
- Event streaming to Kinesis with regional replication

**Gap**: ✅ **Intentional** - Stateless design simplifies DR

### IAM Roles and Policies

**Current State**: Global service, automatically replicated to all regions

**Recovery Mechanism**: **No action needed** - IAM resources survive regional failure

**Dependencies**: None

**Gap**: ✅ **No gap** - IAM is multi-region by default

### Monitoring and Alarms

**Current State**: CloudWatch dashboards, alarms, SNS topics in us-east-1

**Recovery Mechanism**:
1. Run `terragrunt apply` in failover region
2. Observability module recreates dashboards, alarms, SNS in us-west-2
3. Update SNS email subscription (requires user confirmation)
4. No historical metric data transferred (starts fresh)

**Dependencies**: Terraform state must be accessible to know existing config

**Gap**: ⚠️ **Historical metrics lost** - no cross-region metric replication

---

## 4. Numbered DR Runbook (CLI Commands)

### Prerequisites

- AWS CLI configured with credentials (or OIDC via GitHub Actions)
- Terragrunt >= 0.48.0 installed
- Docker installed (for image rebuild)
- Access to GitHub repository: `pallab_paul/genesis-devsecops-pallab`

### Recovery Procedure

**Step 1**: **Verify Regional Outage**

```bash
# Check AWS Service Health Dashboard
aws health describe-events --max-items 10 --region us-east-1

# Verify timeout connects to us-east-1
aws lambda list-functions --region us-east-1 --max-items 1 || echo "Region offline"

# Check if S3 state bucket is accessible (read-only)
aws s3 ls s3://genesis-terraform-state-$(aws sts get-caller-identity --query Account --output text) --region us-east-1 || echo "S3 inaccessible"
```

**Expected Result**: Timeouts or `ServiceUnavailable` errors confirm us-east-1 outage.

---

**Step 2**: **Download Latest Terraform State (if possible)**

```bash
# If S3 is still accessible in read-only mode, download state
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws s3 cp s3://genesis-terraform-state-${AWS_ACCOUNT_ID}/dev/terraform.tfstate \
    ~/dr-backup/terraform-state-$(date +%Y%m%d-%H%M%S).tfstate --region us-east-1 || echo "State unavailable, will import later"
```

**Expected Result**: State file downloaded to `~/dr-backup/` or error if region fully offline.

---

**Step 3**: **Switch to Failover Region**

```bash
# Export failover region
export AWS_REGION=us-west-2
export FAILOVER_REGION=us-west-2

# Update environment config (or use separate dr/ environment)
cd infrastructure/environments/dev
# Edit terragrunt.hcl to change aws_region to us-west-2
```

---

**Step 4**: **Create New S3 State Bucket in Failover Region**

```bash
# Create new state bucket in us-west-2
aws s3api create-bucket \
    --bucket genesis-terraform-state-${AWS_ACCOUNT_ID}-dr \
    --region ${FAILOVER_REGION} \
    --create-bucket-configuration LocationConstraint=${FAILOVER_REGION}

# Enable versioning
aws s3api put-bucket-versioning \
    --bucket genesis-terraform-state-${AWS_ACCOUNT_ID}-dr \
    --versioning-configuration Status=Enabled \
    --region ${FAILOVER_REGION}

# Enable encryption
aws s3api put-bucket-encryption \
    --bucket genesis-terraform-state-${AWS_ACCOUNT_ID}-dr \
    --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' \
    --region ${FAILOVER_REGION}

# Block public access
aws s3api put-public-access-block \
    --bucket genesis-terraform-state-${AWS_ACCOUNT_ID}-dr \
    --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true \
    --region ${FAILOVER_REGION}
```

**Expected Result**: New state bucket ready in us-west-2.

---

**Step 5**: **Rebuild and Push Docker Image to ECR (Failover Region)**

```bash
# Clone repository if not already local
git clone https://github.com/pallab_paul/genesis-devsecops-pallab.git
cd genesis-devsecops-pallab

# Build Docker image
cd app
docker build -t genesis-api:latest .

# Create ECR repository in failover region
aws ecr create-repository \
    --repository-name genesis-api-dev \
    --region ${FAILOVER_REGION} \
    --image-scanning-configuration scanOnPush=true \
    --encryption-configuration encryptionType=AES256

# Login to ECR
aws ecr get-login-password --region ${FAILOVER_REGION} | \
    docker login --username AWS --password-stdin \
    ${AWS_ACCOUNT_ID}.dkr.ecr.${FAILOVER_REGION}.amazonaws.com

# Tag and push image
docker tag genesis-api:latest \
    ${AWS_ACCOUNT_ID}.dkr.ecr.${FAILOVER_REGION}.amazonaws.com/genesis-api-dev:latest
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${FAILOVER_REGION}.amazonaws.com/genesis-api-dev:latest
```

**Expected Result**: Image available in us-west-2 ECR.

---

**Step 6**: **Update Terragrunt Configuration for Failover**

```bash
cd infrastructure/environments/dev

# Update root terragrunt.hcl - change region
sed -i 's/us-east-1/us-west-2/g' ../../terragrunt.hcl
sed -i 's/us-east-1/us-west-2/g' terragrunt.hcl

# Update state bucket name to DR bucket
sed -i "s/genesis-terraform-state-\${get_aws_account_id()}/genesis-terraform-state-${AWS_ACCOUNT_ID}-dr/g" ../../terragrunt.hcl
```

**Expected Result**: Terragrunt configs point to us-west-2 and DR state bucket.

---

**Step 7**: **Initialize Terragrunt in Failover Region**

```bash
cd infrastructure/environments/dev

# Initialize all modules
terragrunt run-all init --terragrunt-non-interactive
```

**Expected Result**: Terraform downloads providers, prepares modules.

---

**Step 8**: **Deploy Infrastructure in Failover Region**

```bash
# Plan deployment
terragrunt run-all plan --terragrunt-non-interactive

# Review plan output carefully - should create all resources fresh

# Apply deployment
terragrunt run-all apply --terragrunt-non-interactive --terragrunt-auto-approve
```

**Expected Result**: All infrastructure created in us-west-2:
- IAM roles (skip if already exist globally)
- Lambda function
- ECR repository (already created in Step 5)
- CloudWatch log group, dashboard, alarms
- SNS topic

---

**Step 9**: **Verify Lambda Function is Running**

```bash
# Get Lambda function details
aws lambda get-function --function-name genesis-api-dev-api --region ${FAILOVER_REGION}

# Get function URL
LAMBDA_URL=$(aws lambda get-function-url-config \
    --function-name genesis-api-dev-api \
    --region ${FAILOVER_REGION} \
    --query 'FunctionUrl' \
    --output text)

echo "Lambda Function URL: ${LAMBDA_URL}"
```

**Expected Result**: Function URL displayed (e.g., `https://abc123.lambda-url.us-west-2.on.aws/`).

---

**Step 10**: **Run Smoke Tests**

```bash
# Test GET /health
curl -s "${LAMBDA_URL}health" | jq .
# Expected: {"status":"ok","version":"1.0.0","env":"dev"}

# Test POST /events
curl -s -X POST "${LAMBDA_URL}events" \
    -H "Content-Type: application/json" \
    -d '{"event_type":"dr_test","description":"DR failover smoke test"}' | jq .
# Expected: 201 Created with event ID

# Test GET /events/{id} (use ID from POST response)
EVENT_ID="<id-from-post-response>"
curl -s "${LAMBDA_URL}events/${EVENT_ID}" | jq .
# Expected: 200 OK with event details
```

**Expected Result**: All 3 endpoints return expected status codes and JSON.

---

**Step 11**: **Update DNS/Service Discovery (if applicable)**

```bash
# If using Route 53 for custom domain:
# aws route53 change-resource-record-sets \
#     --hosted-zone-id Z1234567890ABC \
#     --change-batch file://dns-failover-changeset.json

# For this assessment: Update GitHub Secrets or documentation with new Lambda URL
echo "New Lambda URL: ${LAMBDA_URL}"
echo "Update deployment pipeline AWS_REGION secret to: ${FAILOVER_REGION}"
```

**Expected Result**: Traffic routing updated to failover region.

---

**Step 12**: **Confirm Monitoring is Active**

```bash
# Verify CloudWatch dashboard exists
aws cloudwatch list-dashboards --region ${FAILOVER_REGION} | grep genesis-api-dev

# Verify alarms are created
aws cloudwatch describe-alarms --region ${FAILOVER_REGION} | grep genesis-api-dev

# Verify SNS topic
aws sns list-topics --region ${FAILOVER_REGION} | grep alarms

# Check alarm state (should be OK or INSUFFICIENT_DATA initially)
aws cloudwatch describe-alarms --alarm-names genesis-api-dev-high-error-rate --region ${FAILOVER_REGION}
```

**Expected Result**: Dashboard, 2 alarms, SNS topic all present in us-west-2.

---

**Step 13**: **Notify Stakeholders**

```bash
# Send notification (manual or via SNS)
echo "Subject: Genesis API DR Failover Complete"
echo "Body: Genesis Events API has failed over to us-west-2. New endpoint: ${LAMBDA_URL}"
# Send via email, Slack, PagerDuty, etc.
```

**Expected Result**: Platform team aware of new endpoint URL.

---

**Step 14**: **Document Recovery Time**

```bash
# Calculate actual RTO
OUTAGE_DETECTED="2026-04-11T10:00:00Z"  # Replace with actual time
RECOVERY_COMPLETE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo "Outage detected: ${OUTAGE_DETECTED}"
echo "Recovery complete: ${RECOVERY_COMPLETE}"
echo "Actual RTO: <calculate duration>"

# Log in post-incident review document
```

**Expected Result**: RTO documented for future SLO analysis.

---

### Recovery Validation Checklist

- [ ] Lambda function responds to GET /health with 200
- [ ] POST /events creates event and returns 201
- [ ] GET /events/{id} retrieves event and returns 200
- [ ] CloudWatch dashboard shows lambda metrics
- [ ] Alarms are in OK or INSUFFICIENT_DATA state
- [ ] SNS email subscription confirmed (check inbox)
- [ ] Terraform state is being written to DR bucket
- [ ] GitHub Actions deployment pipeline updated to use us-west-2
- [ ] Stakeholders notified of failover completion

---

## 5. Gap Analysis (Current vs Production-Ready DR)

### Critical Gaps (Would Cause Extended RTO)

| Gap | Impact | Solution | Estimated Cost | Priority |
|-----|--------|----------|----------------|----------|
| **No ECR Cross-Region Replication** | Must rebuild image, adds 30-45 min to RTO | Enable ECR replication to us-west-2 | $0.10/GB replicated | **HIGH** |
| **No S3 State Cross-Region Replication** | State recovery uncertain if region fails | S3 CRR to us-west-2 bucket | $0.02/GB replicated + request costs | **HIGH** |
| **No Automated Failover** | Manual runbook execution, human error risk | AWS Backup, DR automation scripts | Engineering time 2-3 days | **MEDIUM** |
| **No Route 53 Health Checks** | Traffic still routed to failed region | Route 53 weighted routing with health checks | $0.50/health check/month | **MEDIUM** |

### Operational Gaps (Would Cause Data/Visibility Loss)

| Gap | Impact | Solution | Cost | Priority |
|-----|--------|----------|------|----------|
| **No Log Replication** | Last 7-30 days of logs lost | CloudWatch Logs cross-region subscription | $0.50/GB ingested | **LOW** (logs not critical) |
| **No Metric History** | Lose historical CloudWatch data | Cross-region metric streams to S3/Kinesis | $0.03/metric/month | **LOW** |
| **No Warm Standby** | Cold start latency on failover | Maintain Lambda in both regions (passive) | 2× Lambda costs (~$5/month) | **LOW** |

### Planned Enhancements (If Application Were Stateful)

If future versions persist event data to DynamoDB:

| Enhancement | Benefit | Cost |
|-------------|---------|------|
| **DynamoDB Global Tables** | Near-zero RPO (1-2 sec replication lag) | 2× DynamoDB costs |
| **Multi-Region Active-Active** | RTO ≈ DNS TTL (60 seconds) | 2× full infrastructure cost |
| **Cross-Region Read Replicas** | Read traffic survives region failure | 1.5× database costs |

### What Would Be Added with Real Infrastructure Budget

**Immediate** (within 1 month):
1. ECR cross-region replication → Most impactful RTO reduction
2. S3 state CRR → Eliminates state recovery uncertainty
3. Route 53 health checks + failover policy → Automatic DNS failover

**Within 3 months**:
4. Automated DR testing (quarterly simulations)
5. Pre-warmed Lambda in us-west-2 (passive standby)
6. CloudWatch Logs subscription to S3 for centralized logging

**Within 6 months** (if application becomes stateful):
7. DynamoDB global tables for zero data loss
8. Full multi-region active-active deployment

---

## 6. DR Testing Plan

**Frequency**: Quarterly (every 3 months)

**Scope**: Full DR drill executing the runbook from Step 1-14

**Success Criteria**:
- RTO ≤ 4 hours achieved
- All 9 validation checklist items pass
- No critical runbook errors encountered

**Rollback Plan**: Keep us-east-1 resources intact during drill, only create new resources in us-west-2 for testing

**Test Schedule**:
- Q2 2026: Initial DR drill (May 15)
- Q3 2026: DR drill with simulated S3 state unavailability
- Q4 2026: DR drill with Lambda image rebuild required

---

## Conclusion

The current architecture provides a **4-hour RTO with 0 RPO** for regional failure, acceptable for an internal operations tool. The primary gaps are:
1. No ECR cross-region replication (must rebuild image)
2. No S3 state CRR (relies on versioning for recovery)
3. Manual runbook execution (no automation)

With a production infrastructure budget, implementing ECR replication and automated failover would reduce RTO to **30-60 minutes** while maintaining the zero RPO guarantee.

---

**Document Version**: 1.0  
**Last Updated**: April 11, 2026  
**Author**: Pallab Paul  
**Next Review**: After first DR drill (May 15, 2026)
