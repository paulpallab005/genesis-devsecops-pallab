# Bootstrap Guide - Initial AWS Setup

## The Chicken-and-Egg Problem

**Problem Statement**: The CI/CD pipeline requires an IAM role with OIDC federation to authenticate GitHub Actions. However, deploying this IAM role via Terragrunt requires AWS credentials that don't exist yet.

**Solution**: One-time manual bootstrap of the IAM infrastructure, after which all subsequent deployments can be automated via GitHub Actions.

---

## Prerequisites

Before bootstrapping, ensure you have:

1. **AWS Account** with admin access
2. **AWS CLI** configured with admin credentials:
   ```bash
   aws configure
   # Enter: AWS Access Key ID, Secret Access Key, Region (us-east-1)
   ```
3. **Terraform** and **Terragrunt** installed locally
4. **GitHub Repository** created (for OIDC trust policy configuration)

---

## Bootstrap Steps (One-Time Setup)

### Step 1: Create S3 Backend and DynamoDB Lock Table

The Terraform state backend must exist before deploying any modules.

```bash
cd infrastructure

# Get your AWS account ID
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Create S3 bucket for Terraform state
aws s3api create-bucket \
    --bucket genesis-terraform-state-${AWS_ACCOUNT_ID} \
    --region us-east-1

# Enable versioning (required for state recovery)
aws s3api put-bucket-versioning \
    --bucket genesis-terraform-state-${AWS_ACCOUNT_ID} \
    --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
    --bucket genesis-terraform-state-${AWS_ACCOUNT_ID} \
    --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# Block public access (security best practice)
aws s3api put-public-access-block \
    --bucket genesis-terraform-state-${AWS_ACCOUNT_ID} \
    --public-access-block-configuration \
        BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# Create DynamoDB table for state locking
aws dynamodb create-table \
    --table-name genesis-terraform-locks \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region us-east-1

echo "✅ Terraform backend infrastructure created"
```

**Verification**:
```bash
aws s3 ls | grep genesis-terraform-state
aws dynamodb describe-table --table-name genesis-terraform-locks --query 'Table.TableStatus'
```

---

### Step 2: Update GitHub Repository Variable

The IAM trust policy restricts OIDC access to a specific GitHub repository. Update the repository variable:

```bash
# In infrastructure/modules/iam/variables.tf, set default:
variable "github_repository" {
  description = "GitHub repository allowed to assume this role"
  type        = string
  default     = "pallab_paul/genesis-devsecops-pallab"  # UPDATE THIS
}

# Or set via environment variable:
export TF_VAR_github_repository="your-username/your-repo-name"
```

---

### Step 3: Bootstrap IAM Module (Manual Deployment)

Deploy **only the IAM module** using your local AWS admin credentials:

```bash
cd infrastructure/environments/dev/iam

# Initialize Terragrunt
terragrunt init

# Review the plan
terragrunt plan

# Expected output:
#   + aws_iam_openid_connect_provider.github_actions (OIDC provider)
#   + aws_iam_role.github_actions_role (Role for GHA to assume)
#   + aws_iam_role_policy.github_actions_deploy_policy (Permissions: ECR, Lambda, S3, DynamoDB)
#   + aws_iam_role.lambda_execution_role (Role for Lambda function)
#   + 4x aws_iam_role_policy (CloudWatch Logs, Secrets Manager, CloudWatch Metrics, X-Ray)

# Apply the IAM infrastructure
terragrunt apply

# Save outputs (needed for GitHub Actions variables)
terragrunt output -json > ../../outputs/iam-outputs.json
```

**What This Creates**:
1. **OIDC Provider**: `arn:aws:iam::ACCOUNT:oidc-provider/token.actions.githubusercontent.com`
2. **GitHub Actions Role**: `arn:aws:iam::ACCOUNT:role/genesis-api-dev-github-actions-role`
   - Can be assumed by GitHub Actions from your repository
   - Has permissions to deploy Lambda, push to ECR, manage Terraform state
3. **Lambda Execution Role**: `arn:aws:iam::ACCOUNT:role/genesis-api-dev-lambda-execution-role`
   - Used by Lambda function at runtime
   - Has permissions for CloudWatch Logs, Secrets Manager, metrics

---

### Step 4: Configure GitHub Actions variables

Add required repository variables to your GitHub repository:

**Navigate to**: `Settings > Variables > Actions > New repository variable`

| Variable Name | Value | How to Get |
|-------------|-------|-----------|
| `AWS_ACCOUNT_ID` | Your AWS account ID | `aws sts get-caller-identity --query Account --output text` |
| `AWS_REGION` | `us-east-1` | Hardcoded (or your preferred region) |

**Note**: The IAM role ARN is constructed dynamically in the workflow:
```yaml
role-to-assume: arn:aws:iam::${{ env.AWS_ACCOUNT_ID }}:role/genesis-api-dev-github-actions-role
```

---

### Step 5: Test OIDC Authentication

Verify GitHub Actions can assume the role:

**Create a test workflow** `.github/workflows/test-oidc.yml`:
```yaml
name: Test OIDC
on: workflow_dispatch

permissions:
  id-token: write
  contents: read

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v6
        with:
          role-to-assume: arn:aws:iam::${{ env.AWS_ACCOUNT_ID }}:role/genesis-api-dev-github-actions-role
          aws-region: us-east-1
      
      - name: Verify identity
        run: |
          aws sts get-caller-identity
          echo "✅ OIDC authentication successful!"
```

**Run the workflow** and verify it shows:
```json
{
    "UserId": "AROA....:GitHubActions-...",
    "Account": "123456789012",
    "Arn": "arn:aws:sts::123456789012:assumed-role/genesis-api-dev-github-actions-role/GitHubActions-..."
}
```

**Expected**: `Arn` contains `assumed-role/genesis-api-dev-github-actions-role` (not your personal IAM user).

---

### Step 6: Deploy Remaining Infrastructure via GitHub Actions

Now that OIDC is configured, **all subsequent deployments happen via GitHub Actions**:

```bash
# Push to develop branch -> triggers deploy.yml -> deploys to dev
git checkout -b develop
git add .
git commit -m "chore: trigger initial deployment"
git push origin develop

# GitHub Actions will now:
# 1. Authenticate via OIDC (no AWS keys needed!)
# 2. Deploy compute module (Lambda, ECR)
# 3. Deploy observability module (CloudWatch dashboard, alarms)
# 4. Run smoke tests
```

---

## Post-Bootstrap: IAM Role is Self-Managing

After bootstrap, the IAM module becomes **self-managing**:

**Scenario**: You need to add a new IAM policy to the GitHub Actions role.

1. **Edit Terraform code**:
   ```hcl
   # infrastructure/modules/iam/main.tf
   resource "aws_iam_role_policy" "github_actions_new_permission" {
     # New policy allowing CloudFormation access
   }
   ```

2. **Commit and push** to `develop` → GitHub Actions workflow runs:
   ```yaml
   - uses: aws-actions/configure-aws-credentials@v6
     with:
       role-to-assume: arn:aws:iam::123456:role/genesis-api-dev-github-actions-role
   
   - run: terragrunt apply  # Updates the role's own permissions
   ```

3. **IAM role updates itself** because the `github_actions_deploy_policy` includes:
   ```json
   {
     "Effect": "Allow",
     "Action": [
       "iam:GetRole",
       "iam:UpdateAssumeRolePolicy",
       "iam:PutRolePolicy",
       "iam:DeleteRolePolicy"
     ],
     "Resource": "arn:aws:iam::*:role/genesis-api-*"
   }
   ```

---

## Security Note: Removing Admin Credentials

After bootstrap is complete:

1. **Revoke temporary admin credentials** used for bootstrap:
   ```bash
   aws iam delete-access-key --access-key-id AKIA...
   ```

2. **Document that OIDC is now the only authentication method**:
   - No AWS access keys in GitHub Secrets ✅
   - No long-lived credentials ✅
   - Auto-rotating session tokens (1 hour TTL) ✅

3. **Update `.gitignore`** to prevent credential leakage:
   ```
   # AWS credentials
   .aws/
   *.pem
   *_accessKeys.csv
   ```

---

## Alternative: LocalStack Bootstrap (Assessment/Testing)

If you don't have AWS access, you can demonstrate the bootstrap process using **LocalStack**:

```bash
# Start LocalStack
docker run -d -p 4566:4566 localstack/localstack

# Set LocalStack endpoint
export AWS_ENDPOINT_URL=http://localhost:4566
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test

# Run bootstrap commands against LocalStack
cd infrastructure/environments/dev/iam
terragrunt init
terragrunt apply --terragrunt-non-interactive

# Verify resources created
aws --endpoint-url=http://localhost:4566 iam list-roles | grep genesis-api
```

---

## Troubleshooting

### Error: "User is not authorized to perform: sts:AssumeRoleWithWebIdentity"

**Cause**: OIDC provider's trust policy doesn't match the GitHub repository.

**Fix**: Verify the trust policy condition:
```bash
aws iam get-role --role-name genesis-api-dev-github-actions-role \
  --query 'Role.AssumeRolePolicyDocument.Statement[0].Condition'
```

**Expected**:
```json
{
  "StringLike": {
    "token.actions.githubusercontent.com:sub": "repo:pallab_paul/genesis-devsecops-pallab:*"
  }
}
```

If repository name is wrong, update `infrastructure/modules/iam/main.tf` and re-run bootstrap.

---

### Error: "Error creating S3 bucket: BucketAlreadyExists"

**Cause**: Bucket name collision (S3 bucket names are globally unique).

**Fix**: Add a unique suffix to the bucket name:
```bash
# In infrastructure/terragrunt.hcl
remote_state {
  backend = "s3"
  config = {
    bucket = "genesis-terraform-state-${get_aws_account_id()}-${random_suffix}"
  }
}
```

---

## Summary

**One-Time Bootstrap Checklist**:
- [ ] Create S3 state bucket with versioning/encryption
- [ ] Create DynamoDB lock table
- [ ] Update GitHub repository variable in IAM module
- [ ] Deploy IAM module locally (`terragrunt apply`)
- [ ] Add `AWS_ACCOUNT_ID` as a GitHub Actions repository variable
- [ ] Test OIDC authentication with test workflow
- [ ] Delete local admin AWS credentials
- [ ] All future deployments happen via GitHub Actions ✅

**Why This Works**:
- Bootstrap creates the "ladder" (OIDC role)
- GitHub Actions climbs the ladder (assumes the role)
- Ladder maintains itself (role updates its own policies via Terragrunt)
- No permanent credentials needed after initial setup

---

**Document Version**: 1.0  
**Last Updated**: April 11, 2026  
**Author**: Pallab Paul  
**Next Steps**: Test OIDC authentication, then trigger first automated deployment
