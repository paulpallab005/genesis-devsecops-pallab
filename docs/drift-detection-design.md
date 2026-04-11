# Drift Detection Strategy - Genesis Events API

## Overview

Infrastructure drift occurs when the actual state of cloud resources diverges from the desired state defined in Terraform configuration. This document defines the automated drift detection mechanism, response policy, and Terragrunt-specific advantages for the Genesis Events API infrastructure.

---

## 1. Detection Mechanism

### Automated Daily Drift Detection

We implement **nightly drift detection** using GitHub Actions scheduled workflows that execute Terragrunt plan operations across all environments and modules.

**Implementation**:

```yaml
name: Drift Detection
on:
  schedule:
    - cron: '0 2 * * *'  # 2 AM UTC daily
  workflow_dispatch:     # Manual trigger option

jobs:
  detect-drift:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        environment: [dev, prod]
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      
      - name: Configure AWS (OIDC)
        uses: aws-actions/configure-aws-credentials@v6
        with:
          role-to-assume: ${{ secrets.DRIFT_DETECTION_ROLE_ARN }}
          aws-region: us-east-1
      
      - name: Setup Terragrunt
        uses: autero1/action-terragrunt@v3
      
      - name: Run drift detection
        id: drift
        run: |
          cd infrastructure/environments/${{ matrix.environment }}
          terragrunt run-all plan --terragrunt-non-interactive --detailed-exitcode
        continue-on-error: true
      
      - name: Evaluate drift status
        run: |
          EXIT_CODE=${{ steps.drift.outcome }}
          if [ "$EXIT_CODE" == "failure" ]; then
            echo "DRIFT_DETECTED=true" >> $GITHUB_ENV
            echo "Drift detected in ${{ matrix.environment }} environment"
          else
            echo "DRIFT_DETECTED=false" >> $GITHUB_ENV
            echo "No drift in ${{ matrix.environment }} environment"
          fi
      
      - name: Create GitHub Issue on drift
        if: env.DRIFT_DETECTED == 'true'
        uses: actions/github-script@v7
        with:
          script: |
            github.rest.issues.create({
              owner: context.repo.owner,
              repo: context.repo.repo,
              title: `Infrastructure Drift Detected - ${{ matrix.environment }}`,
              body: `## ⚠️ Drift Alert\n\n**Environment**: ${{ matrix.environment }}\n**Detection Time**: ${new Date().toISOString()}\n**Action Required**: Review Terragrunt plan output and reconcile within SLA.\n\nSee workflow run: ${context.serverUrl}/${context.repo.owner}/${context.repo.repo}/actions/runs/${context.runId}`,
              labels: ['infrastructure', 'drift', 'ops', `env:${{ matrix.environment }}`]
            })
      
      - name: Upload plan output
        if: env.DRIFT_DETECTED == 'true'
        uses: actions/upload-artifact@v4
        with:
          name: drift-plan-${{ matrix.environment }}-${{ github.run_id }}
          path: infrastructure/environments/${{ matrix.environment }}/**/*.tfplan
          retention-days: 30
```

**How Exit Codes Work**:
- **Exit Code 0**: No changes needed (no drift)
- **Exit Code 1**: Error occurred (plan failed)
- **Exit Code 2**: Changes detected (drift found)

Using `--detailed-exitcode` allows us to distinguish between "no drift" and "drift detected" programmatically.

### Notification Channels

When drift is detected, the system:
1. **Creates GitHub Issue** with drift details and workflow link
2. **Sends Slack notification** (if webhook configured) to #infrastructure-alerts channel
3. **Tags on-call engineer** based on environment severity (prod = page, dev = Slack only)
4. **Uploads Terragrunt plan artifact** for detailed review

### Detection Scope

The nightly job checks **all modules in all environments**:
- IAM module (roles, policies, OIDC provider)
- Compute module (Lambda, ECR, Function URL)
- Observability module (dashboards, alarms, SNS)
- Networking module (VPC - when implemented)

Using `terragrunt run-all plan` ensures we detect drift across the entire dependency graph, including upstream dependencies that might affect downstream resources.

---

## 2. Response Policy and SLAs

### Drift Classification

| Drift Type | Example | Severity | SLA to Reconcile |
|------------|---------|----------|------------------|
| **Critical (Prod)** | Lambda function code changed, IAM policy modified manually | 🔴 High | **24 hours** |
| **Standard (Prod)** | Log retention changed, tag added/removed | 🟡 Medium | **48 hours** |
| **Low (Dev)** | Any drift in dev environment | 🟢 Low | **1 week** |
| **Accepted Drift** | Incident hotfix approved by change management | ✅ Exempt | Update IaC within 48 hours |

### Reconciliation Process

**Step 1 - Triage** (Within 2 hours of detection):
1. On-call engineer reviews GitHub issue and plan artifact
2. Determine cause: manual change, API drift, or Terraform bug
3. Classify severity using table above
4. If production critical: start incident process

**Step 2 - Root Cause Analysis**:
- **Manual Change**: Check CloudTrail for who/when/what
- **AWS API Drift**: Some AWS resources auto-update (e.g., Lambda platform version)
- **Terraform Bug**: Provider behavior changed between versions

**Step 3 - Remediation** (Choose one):

**Option A - Revert to IaC** (Preferred):
```bash
# Discard manual changes, apply Terraform-defined state
cd infrastructure/environments/prod
terragrunt run-all apply --terragrunt-non-interactive
```

**Option B - Update IaC to Match Reality** (If manual change was valid):
```bash
# Import actual state into Terraform
cd infrastructure/modules/compute
terraform import aws_lambda_function.api <function-name>

# Or manually edit .tf files to match new desired state
# Then commit and merge PR
```

**Option C - Accept Drift Temporarily** (Incident hotfixes only):
- Document in GitHub issue why drift is accepted
- Create follow-up task to update IaC within 48 hours
- Add exception to drift detection (if recurring API behavior)

**Step 4 - Verification**:
- Re-run `terragrunt plan` to confirm zero drift
- Update GitHub issue with resolution notes
- Close issue and post to #infrastructure-resolved channel

### When Drift is Acceptable

**Scenario 1 - Incident Hotfix**:
- Production is down at 3 AM
- On-call makes AWS console change to restore service immediately
- Drift accepted for 48 hours while post-incident PR updates IaC

**Scenario 2 - AWS-Managed Changes**:
- Lambda platform updates (e.g., Python runtime patches)
- AWS adds new default tags to resources
- Add to `.gitignore` equivalent in Terraform: `lifecycle { ignore_changes = [...] }`

**Scenario 3 - Terraform Provider Bug**:
- Known issue where `terraform plan` always shows change
- Document in `# checkov:skip` comment style: `# drift:ignore=reason`

### Escalation Path

- **24-hour SLA missed**: Auto-escalate to Engineering Manager
- **72-hour SLA missed**: Executive report required (CTO/VP Engineering)
- **Prod critical drift**: Page on-call immediately, no waiting for nightly job

---

## 3. Terragrunt-Specific Advantages for Drift Detection

### Advantage 1: Module Isolation with Granular State

**The Problem with Monolithic Terraform**:
- Single large state file (e.g., `terraform.tfstate` with 200 resources)
- Drift detection runs `terraform plan` on all 200 resources
- Output is overwhelming: "20 resources changed" unclear which system is affected
- Long plan time increases drift window

**Terragrunt Solution**:
- **Isolated state per module**: IAM has own state, Compute has own state, Observability has own state
- Drift detection runs `terragrunt plan` per module directory
- Clear attribution: "Compute module has drift" vs. "IAM module clean"
- Fast parallel detection: `terragrunt run-all plan --terragrunt-parallelism 4`

**Example Output**:
```
[IAM]           ✅ No changes. Infrastructure is up-to-date.
[Compute]       ⚠️  Terraform will perform the following actions:
                    ~ aws_lambda_function.api
                      memory_size: 512 → 1024
[Observability] ✅ No changes. Infrastructure is up-to-date.
[Networking]    ✅ No changes. Infrastructure is up-to-date.
```

**Result**: Team immediately knows "Compute module drifted, Lambda memory changed" without parsing 200-line diff.

### Advantage 2: Dependency-Aware Drift Impact Analysis

**The Problem with Standalone Modules**:
- Drift in upstream module (e.g., IAM role ARN changed manually)
- Downstream modules (e.g., Lambda using that role) now have "phantom drift"
- Hard to determine root cause: is Lambda drifted or is IAM drifted?

**Terragrunt Solution**:
- **Dependency graph defined in `terragrunt.hcl`**:
  ```hcl
  dependency "iam" {
    config_path = "../iam"
  }
  inputs = {
    lambda_execution_role_arn = dependency.iam.outputs.lambda_execution_role_arn
  }
  ```
- Drift detection can trace: "Lambda shows drift because IAM role ARN changed"
- Fix root cause (IAM), downstream modules auto-reconcile on next apply

**Example Scenario**:
1. Someone manually edits IAM trust policy in AWS console
2. IAM module: `aws_iam_role.lambda_execution_role` shows drift
3. Compute module: `aws_lambda_function.api` shows drift (role ARN hash changed)
4. Terragrunt dependency graph reveals: **Fix IAM first, Compute will follow**

**Result**: Reduced false positives and faster root cause identification.

### Advantage 3: Environment-Specific Drift Tolerance

**The Problem with Shared Configuration**:
- Dev and Prod use same Terraform modules
- Dev drift acceptable (engineers testing), Prod drift is critical
- Can't set different detection policies per environment

**Terragrunt Solution**:
- **Environment-specific configuration in `environments/dev/` vs. `environments/prod/`**
- Different drift detection schedules:
  - Dev: Check weekly (less noise)
  - Prod: Check nightly (strict monitoring)
- Different response SLAs:
  - Dev: 1 week to reconcile
  - Prod: 24 hours to reconcile

**Implementation**:
```yaml
# .github/workflows/drift-detection.yml
strategy:
  matrix:
    environment: [dev, prod]
    include:
      - environment: dev
        severity: low
        sla: "1 week"
      - environment: prod
        severity: high
        sla: "24 hours"
```

**Result**: Right level of alerts for each environment, no alert fatigue.

### Advantage 4: DRY Configuration Reduces Drift Surface

**The Problem with Copy-Paste IaC**:
- Separate Terraform code for dev and prod
- Drift in dev doesn't alert for prod (configurations diverged)
- High maintenance: must update drift policies in 2 places

**Terragrunt Solution**:
- **Single module definition in `infrastructure/modules/`**
- **Environment-specific inputs only in `environments/`**
- Drift detection logic is identical across environments (DRY)
- Reduced drift surface: only variable values change, not structure

**Example**:
```
infrastructure/
  modules/compute/main.tf          ← Single source of truth for Lambda config
  environments/dev/compute/        ← Only memory_size = 512 differs
  environments/prod/compute/       ← Only memory_size = 1024 differs
```

**Drift Check**:
- Both dev and prod use same `aws_lambda_function` resource definition
- Drift in resource structure (e.g., new `reserved_concurrent_executions` added manually) detected in both environments
- Only input variables can differ without triggering false positives

**Result**: Consistent drift detection across all environments with minimal configuration.

---

## 4. Automated Remediation (Future Enhancement)

### Current State: Alert Only

The nightly job **detects and alerts**, but does **not auto-remediate**. Human approval required for all fixes.

### Future: Auto-Remediate Dev, Alert for Prod

**Proposed Logic**:
```yaml
- name: Auto-remediate dev drift
  if: matrix.environment == 'dev' && env.DRIFT_DETECTED == 'true'
  run: |
    terragrunt run-all apply --terragrunt-non-interactive --auto-approve
    echo "Dev drift auto-remediated, IaC state restored"

- name: Create approval request for prod drift
  if: matrix.environment == 'prod' && env.DRIFT_DETECTED == 'true'
  uses: trstringer/manual-approval@v1
  with:
    approvers: platform-team
    minimum-approvals: 2
    issue-title: "Prod Drift - Approval Required to Remediate"
```

**Benefits**:
- Dev environment self-heals overnight (reduces toil)
- Prod requires human review (prevents accidental reverts of valid changes)

**Risk**: Auto-remediation could revert valid emergency hotfixes. Mitigation: require `[drift:ignore]` tag in AWS resource tags to exempt from auto-fix.

---

## 5. Metrics and Reporting

### Drift Detection Metrics (Tracked in DataDog/CloudWatch)

| Metric | Threshold | Alert |
|--------|-----------|-------|
| `drift_detection.runs` | N/A | Track daily |
| `drift_detection.failures` (exit code 1) | >0 | Immediate (broken detection) |
| `drift_detection.drift_found` (exit code 2) | >2 per week in prod | Investigate manual change patterns |
| `drift_sla.time_to_resolve` | >24h for prod critical | Escalate to management |

### Monthly Drift Report

Auto-generate report from GitHub Issues with `drift` label:
- **Total drift incidents this month**: 5
- **Average time to resolve**: 18 hours (within 24h SLA ✅)
- **Most common drift type**: Lambda memory_size changes (4/5)
- **Action item**: Add Lambda memory to environment variables, educate team on IaC-first changes

---

## Summary

Our drift detection strategy provides:
1. **Automated nightly detection** using `terragrunt plan --detailed-exitcode`
2. **Clear SLAs**: 24h for prod critical, 1 week for dev
3. **GitHub Issues for tracking** with workflow artifacts
4. **Terragrunt advantages**: Module isolation, dependency-aware analysis, environment-specific policies, DRY configuration

This ensures infrastructure remains in the desired state defined in Git while allowing for legitimate emergency changes with proper follow-up processes.

---

**Document Version**: 1.0  
**Last Updated**: April 11, 2026  
**Author**: Pallab Paul  
**Next Review**: After first month of production drift data (May 15, 2026)
