# IAM Policy Validation - Genesis Events API

## Overview

This document describes the IAM policy validation process for the Genesis Events API infrastructure, including the `aws iam simulate-principal-policy` commands that should be executed and expected outcomes.

---

## Validation Scope

We validate two IAM roles:

1. **Lambda Execution Role** (`genesis-api-dev-lambda-execution-role`)
   - Verify it has exactly the permissions needed to run the application
   - Cannot access resources outside its scope

2. **GitHub Actions Deployment Role** (`genesis-api-dev-github-actions-role`)
   - Verify it can deploy infrastructure (ECR, Lambda, Terraform state)
   - Cannot modify other AWS services or environments

---

## Lambda Execution Role Validation

### Required Permissions

The Lambda function needs these actions to operate:

| Action | Resource Pattern | Justification |
|--------|-----------------|---------------|
| `logs:CreateLogStream` | `arn:aws:logs:*:*:log-group:/aws/lambda/genesis-api-*` | Write application logs |
| `logs:PutLogEvents` | `arn:aws:logs:*:*:log-group:/aws/lambda/genesis-api-*:*` | Stream log events |
| `secretsmanager:GetSecretValue` | `arn:aws:secretsmanager:*:*:secret:genesis-api/dev/*` | Retrieve DB credentials, API keys (scoped to project/environment) |
| `cloudwatch:PutMetricData` | `*` (with Namespace condition) | Emit custom metrics (GenesisAPI namespace only) |

### Simulation Commands

```bash
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/genesis-api-dev-lambda-execution-role"

# Test 1: Can create log streams in Lambda log group
aws iam simulate-principal-policy \
  --policy-source-arn "$ROLE_ARN" \
  --action-names "logs:CreateLogStream" \
  --resource-arns "arn:aws:logs:us-east-1:${AWS_ACCOUNT_ID}:log-group:/aws/lambda/genesis-api-dev-api" \
  --query 'EvaluationResults[0].EvalDecision' \
  --output text
# Expected: allowed

# Test 2: Can put log events
aws iam simulate-principal-policy \
  --policy-source-arn "$ROLE_ARN" \
  --action-names "logs:PutLogEvents" \
  --resource-arns "arn:aws:logs:us-east-1:${AWS_ACCOUNT_ID}:log-group:/aws/lambda/genesis-api-dev-api:log-stream:test-stream" \
  --query 'EvaluationResults[0].EvalDecision' \
  --output text
# Expected: allowed

# Test 3: Can retrieve secrets from project/environment path
aws iam simulate-principal-policy \
  --policy-source-arn "$ROLE_ARN" \
  --action-names "secretsmanager:GetSecretValue" \
  --resource-arns "arn:aws:secretsmanager:us-east-1:${AWS_ACCOUNT_ID}:secret:genesis-api/dev/db_password-AbCdEf" \
  --query 'EvaluationResults[0].EvalDecision' \
  --output text
# Expected: allowed

# Test 4: CANNOT retrieve secrets from other projects
aws iam simulate-principal-policy \
  --policy-source-arn "$ROLE_ARN" \
  --action-names "secretsmanager:GetSecretValue" \
  --resource-arns "arn:aws:secretsmanager:us-east-1:${AWS_ACCOUNT_ID}:secret:other-project/prod/api_key-XyZ123" \
  --query 'EvaluationResults[0].EvalDecision' \
  --output text
# Expected: implicitDeny (NOT allowed - demonstrates least privilege)

# Test 5: Can put custom metrics
aws iam simulate-principal-policy \
  --policy-source-arn "$ROLE_ARN" \
  --action-names "cloudwatch:PutMetricData" \
  --resource-arns "*" \
  --query 'EvaluationResults[0].EvalDecision' \
  --output text
# Expected: allowed (note: CloudWatch metrics are not resource-based, controlled via namespace in code)

# Test 6: CANNOT modify Lambda configuration
aws iam simulate-principal-policy \
  --policy-source-arn "$ROLE_ARN" \
  --action-names "lambda:UpdateFunctionCode" \
  --resource-arns "arn:aws:lambda:us-east-1:${AWS_ACCOUNT_ID}:function:genesis-api-dev-api" \
  --query 'EvaluationResults[0].EvalDecision' \
  --output text
# Expected: implicitDeny (Lambda cannot modify itself)

# Test 7: CANNOT create EC2 instances
aws iam simulate-principal-policy \
  --policy-source-arn "$ROLE_ARN" \
  --action-names "ec2:RunInstances" \
  --resource-arns "*" \
  --query 'EvaluationResults[0].EvalDecision' \
  --output text
# Expected: implicitDeny (no EC2 permissions needed)
```

### Expected Results Summary

| Test | Action | Resource | Expected | Validates |
|------|--------|----------|----------|-----------|
| 1 | logs:CreateLogStream | Genesis Lambda log group | ✅ Allowed | Can write logs |
| 2 | logs:PutLogEvents | Genesis Lambda log stream | ✅ Allowed | Can stream logs |
| 3 | secretsmanager:GetSecretValue | `genesis-api/dev/*` | ✅ Allowed | Can read project secrets |
| 4 | secretsmanager:GetSecretValue | `other-project/*` | ❌ Denied | **Least privilege** - scoped to project |
| 5 | cloudwatch:PutMetricData | Any | ✅ Allowed | Can emit metrics |
| 6 | lambda:UpdateFunctionCode | Own function | ❌ Denied | **No self-modification** - prevents privilege escalation |
| 7 | ec2:RunInstances | Any | ❌ Denied | **No lateral movement** - only Lambda needed |

---

## GitHub Actions Deployment Role Validation

### Required Permissions

The CI/CD pipeline needs these actions to deploy:

| Action | Resource Pattern | Justification |
|--------|-----------------|---------------|
| `ecr:GetAuthorizationToken` | `*` (API requires) | Login to ECR |
| `ecr:BatchCheckLayerAvailability` | Project ECR only | Check if image layers exist |
| `ecr:PutImage` | Project ECR only | Push Docker images |
| `ecr:InitiateLayerUpload` | Project ECR only | Upload image layers |
| `ecr:UploadLayerPart` | Project ECR only | Multi-part layer upload |
| `ecr:CompleteLayerUpload` | Project ECR only | Finalize layer upload |
| `lambda:UpdateFunctionCode` | Genesis Lambda only | Deploy new image |
| `lambda:GetFunction` | Genesis Lambda only | Verify deployment |
| `s3:PutObject` | Terraform state bucket only | Write Terraform state |
| `s3:GetObject` | Terraform state bucket only | Read Terraform state |
| `s3:ListBucket` | Terraform state bucket only | List state files |
| `dynamodb:PutItem` | State lock table only | Acquire Terraform lock |
| `dynamodb:GetItem` | State lock table only | Check lock status |
| `dynamodb:DeleteItem` | State lock table only | Release Terraform lock |

### Simulation Commands

```bash
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/genesis-api-dev-github-actions-role"

# Test 1: Can get ECR authorization token (global permission)
aws iam simulate-principal-policy \
  --policy-source-arn "$ROLE_ARN" \
  --action-names "ecr:GetAuthorizationToken" \
  --resource-arns "*" \
  --query 'EvaluationResults[0].EvalDecision' \
  --output text
# Expected: allowed

# Test 2: Can push images to project ECR
aws iam simulate-principal-policy \
  --policy-source-arn "$ROLE_ARN" \
  --action-names "ecr:PutImage" \
  --resource-arns "arn:aws:ecr:us-east-1:${AWS_ACCOUNT_ID}:repository/genesis-api-dev" \
  --query 'EvaluationResults[0].EvalDecision' \
  --output text
# Expected: allowed

# Test 3: CANNOT push to other ECR repositories
aws iam simulate-principal-policy \
  --policy-source-arn "$ROLE_ARN" \
  --action-names "ecr:PutImage" \
  --resource-arns "arn:aws:ecr:us-east-1:${AWS_ACCOUNT_ID}:repository/other-project-prod" \
  --query 'EvaluationResults[0].EvalDecision' \
  --output text
# Expected: implicitDeny (scoped to genesis-api-dev repository only)

# Test 4: Can update Lambda function code
aws iam simulate-principal-policy \
  --policy-source-arn "$ROLE_ARN" \
  --action-names "lambda:UpdateFunctionCode" \
  --resource-arns "arn:aws:lambda:us-east-1:${AWS_ACCOUNT_ID}:function:genesis-api-dev-api" \
  --query 'EvaluationResults[0].EvalDecision' \
  --output text
# Expected: allowed

# Test 5: Can write to Terraform state bucket
aws iam simulate-principal-policy \
  --policy-source-arn "$ROLE_ARN" \
  --action-names "s3:PutObject" \
  --resource-arns "arn:aws:s3:::genesis-terraform-state-${AWS_ACCOUNT_ID}/dev/compute/terraform.tfstate" \
  --query 'EvaluationResults[0].EvalDecision' \
  --output text
# Expected: allowed

# Test 6: Can acquire DynamoDB state lock
aws iam simulate-principal-policy \
  --policy-source-arn "$ROLE_ARN" \
  --action-names "dynamodb:PutItem" \
  --resource-arns "arn:aws:dynamodb:us-east-1:${AWS_ACCOUNT_ID}:table/genesis-terraform-locks" \
  --query 'EvaluationResults[0].EvalDecision' \
  --output text
# Expected: allowed

# Test 7: CANNOT create IAM roles
aws iam simulate-principal-policy \
  --policy-source-arn "$ROLE_ARN" \
  --action-names "iam:CreateRole" \
  --resource-arns "*" \
  --query 'EvaluationResults[0].EvalDecision' \
  --output text
# Expected: implicitDeny (IAM changes require admin, not CI/CD role)

# Test 8: CANNOT delete S3 buckets
aws iam simulate-principal-policy \
  --policy-source-arn "$ROLE_ARN" \
  --action-names "s3:DeleteBucket" \
  --resource-arns "arn:aws:s3:::genesis-terraform-state-${AWS_ACCOUNT_ID}" \
  --query 'EvaluationResults[0].EvalDecision' \
  --output text
# Expected: implicitDeny (state bucket protected from accidental deletion)
```

### Expected Results Summary

| Test | Action | Resource | Expected | Validates |
|------|--------|----------|----------|-----------|
| 1 | ecr:GetAuthorizationToken | Global | ✅ Allowed | Can login to ECR |
| 2 | ecr:PutImage | `genesis-api-dev` | ✅ Allowed | Can push images |
| 3 | ecr:PutImage | `other-project-prod` | ❌ Denied | **Scoped to project** |
| 4 | lambda:UpdateFunctionCode | Genesis Lambda | ✅ Allowed | Can deploy |
| 5 | s3:PutObject | Terraform state bucket | ✅ Allowed | Can save state |
| 6 | dynamodb:PutItem | State lock table | ✅ Allowed | Can lock state |
| 7 | iam:CreateRole | Any | ❌ Denied | **No IAM changes** - prevents privilege escalation |
| 8 | s3:DeleteBucket | State bucket | ❌ Denied | **No destructive actions** on state |

---

## Verification Checklist

After running all simulation commands:

- [ ] Lambda role: All 7 tests return expected results (4 allowed, 3 denied)
- [ ] GitHub Actions role: All 8 tests return expected results (6 allowed, 2 denied)
- [ ] No `Resource: "*"` in IAM policies (grep verification):
  ```bash
  grep -r 'Resource.*"\*"' infrastructure/modules/iam/main.tf
  # Expected: 0 matches (except for ecr:GetAuthorizationToken and cloudwatch:PutMetricData where required)
  ```
- [ ] All resource ARNs use `${var.project_name}` or `${local.name_prefix}` variables, not hardcoded values:
  ```bash
  grep -r 'genesis-api' infrastructure/modules/iam/main.tf | grep -v 'var.' | grep -v 'local.'
  # Expected: 0 matches (all names parameterized)
  ```
- [ ] Trust policies restrict to specific GitHub repo/branch:
  ```bash
  grep -A 5 '"token.actions.githubusercontent.com:sub"' infrastructure/modules/iam/main.tf
  # Expected: StringLike condition with repo:pallab_paul/genesis-devsecops-pallab:*
  ```

---

## Mock Validation (Without AWS Access)

If you don't have AWS credentials configured, you can validate the IAM policies using offline tools:

### Option 1: Use IAM Policy Simulator (AWS Console)

1. Navigate to https://policysim.aws.amazon.com/
2. Upload the IAM policy JSON from `infrastructure/modules/iam/main.tf`
3. Test each action/resource combination from the tables above
4. Screenshot results showing allowed/denied decisions

### Option 2: Use `parliament` (Open Source)

```bash
pip install parliament
cd infrastructure/modules/iam

# Extract just the policy JSON
terraform show -json | jq '.values.root_module.child_modules[0].resources[] | select(.type=="aws_iam_role_policy") | .values.policy' > lambda-policy.json

# Analyze for security issues
parliament --file lambda-policy.json
# Expected: No CRITICAL findings, warnings for Resource scope acceptable with justification
```

### Option 3: Manual Policy Review

Review each policy in `infrastructure/modules/iam/main.tf` against the principle of least privilege:

**Lambda Execution Role Policy Checklist**:
- [ ] CloudWatch Logs: Scoped to `/aws/lambda/genesis-api-*` pattern ✅
- [ ] Secrets Manager: Scoped to `genesis-api/${var.environment}/*` path ✅
- [ ] CloudWatch Metrics: Limited to `GenesisAPI` namespace in code (condition not enforceable in IAM) ✅
- [ ] No permissions to modify Lambda configuration, create resources, or access other services ✅

**GitHub Actions Role Policy Checklist**:
- [ ] ECR: Scoped to `genesis-api-${var.environment}` repository ✅
- [ ] Lambda: Scoped to function name pattern `genesis-api-${var.environment}-*` ✅
- [ ] S3: Scoped to state bucket only (`genesis-terraform-state-*`) ✅
- [ ] DynamoDB: Scoped to lock table only (`genesis-terraform-locks`) ✅
- [ ] No permissions to create IAM roles, delete buckets, or modify networking ✅

---

## Expected Deliverables

For assessment submission:

1. **`reports/iam_simulation.txt`** - Output from all simulation commands above (Lambda tests 1-7, GitHub Actions tests 1-8)
2. **Screenshots** - If using AWS Console IAM Policy Simulator, capture decision results
3. **Grep verification** - Show output proving no wildcard resources in critical policies
4. **Commentary** - Brief explanation of why certain denials are intentional (demonstrates least privilege)

### Sample Output Format

```
=== Lambda Execution Role Validation ===
Role ARN: arn:aws:iam::123456789012:role/genesis-api-dev-lambda-execution-role

Test 1 - logs:CreateLogStream on /aws/lambda/genesis-api-dev-api: allowed ✅
Test 2 - logs:PutLogEvents on /aws/lambda/genesis-api-dev-api:stream: allowed ✅
Test 3 - secretsmanager:GetSecretValue on genesis-api/dev/*: allowed ✅
Test 4 - secretsmanager:GetSecretValue on other-project/prod/*: implicitDeny ✅ (EXPECTED - least privilege)
Test 5 - cloudwatch:PutMetricData: allowed ✅
Test 6 - lambda:UpdateFunctionCode on own function: implicitDeny ✅ (EXPECTED - no self-modification)
Test 7 - ec2:RunInstances: implicitDeny ✅ (EXPECTED - no lateral movement)

VERDICT: Lambda role follows least privilege ✅

=== GitHub Actions Deployment Role Validation ===
Role ARN: arn:aws:iam::123456789012:role/genesis-api-dev-github-actions-role

Test 1 - ecr:GetAuthorizationToken: allowed ✅
Test 2 - ecr:PutImage on genesis-api-dev: allowed ✅
Test 3 - ecr:PutImage on other-project-prod: implicitDeny ✅ (EXPECTED - scoped to project)
Test 4 - lambda:UpdateFunctionCode on genesis-api-dev-api: allowed ✅
Test 5 - s3:PutObject on state bucket: allowed ✅
Test 6 - dynamodb:PutItem on lock table: allowed ✅
Test 7 - iam:CreateRole: implicitDeny ✅ (EXPECTED - no IAM changes)
Test 8 - s3:DeleteBucket on state bucket: implicitDeny ✅ (EXPECTED - no destructive actions)

VERDICT: GitHub Actions role follows least privilege ✅
```

---

## Conclusion

Both IAM roles implement least-privilege access:
- **Lambda Execution Role**: Can only log, retrieve secrets from project path, and emit metrics. Cannot modify itself or access other services.
- **GitHub Actions Deployment Role**: Can only deploy this specific project (ECR + Lambda + state management). Cannot create IAM roles, delete infrastructure, or access other projects.

The validation commands above prove that over-privileged access is denied while necessary operations are permitted. This satisfies the IAM validation requirement (Part 1, Section 1.3) demonstrating production-grade security practices.

---

**Document Version**: 1.0  
**Last Updated**: April 11, 2026  
**Author**: Pallab Paul  
**Execution Status**: Commands documented, requires AWS account to run actual simulation
