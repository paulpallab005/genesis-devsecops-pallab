# IAM Module

This module provisions IAM roles and OIDC provider for secure authentication and authorization in the Genesis Events API infrastructure.

## Purpose

Creates least-privilege IAM roles for:
1. **GitHub Actions deployment**: Uses OIDC federation (no static AWS credentials)
2. **Lambda execution**: Scoped permissions for CloudWatch logs, Secrets Manager, and custom metrics

## Features

- **OIDC Authentication**: GitHub Actions authenticates via OIDC provider (no AWS access keys required)
- **Least-Privilege Policies**: All roles have minimal permissions scoped to specific resources
- **Resource-Scoped Actions**: Lambda and deployment roles limited to project-specific resources
- **Condition-Based Access**: OIDC role restricted to specific GitHub repo and branch

## Usage

```hcl
module "iam" {
  source = "../../modules/iam"
  
  aws_region    = "us-east-1"
  environment   = "dev"
  project       = "genesis-api"
  owner         = "pallab"
  
  github_org    = "paulpallab005"
  github_repo   = "genesis-devsecops-pallab"
  github_branch = "main"
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| aws_region | AWS region for IAM resources | string | us-east-1 | no |
| environment | Environment name (dev, prod, staging) | string | - | yes |
| project | Project name for resource naming | string | genesis-api | no |
| owner | Owner/team responsible for resources | string | pallab | no |
| github_org | GitHub organization or username | string | - | yes |
| github_repo | GitHub repository name (without org) | string | - | yes |
| github_branch | Branch allowed to deploy (default: main) | string | main | no |

## Outputs

| Name | Description |
|------|-------------|
| github_actions_role_arn | ARN of IAM role for GitHub Actions (use in workflows) |
| github_actions_role_name | Name of GitHub Actions role |
| lambda_execution_role_arn | ARN of Lambda execution role (pass to compute module) |
| lambda_execution_role_name | Name of Lambda execution role |
| oidc_provider_arn | ARN of GitHub OIDC provider |
| oidc_provider_url | URL of OIDC provider |

## Security Design

### GitHub Actions Role Permissions

- **ECR**: Push/pull container images
- **Lambda**: Update function code and configuration
- **S3**: Read/write Terraform state
- **DynamoDB**:  Lock table access for state locking

**Trust Policy**: Only allows assumption from specified GitHub repo and branch via OIDC.

### Lambda Execution Role Permissions

- **CloudWatch Logs**: Create log groups/streams, write logs (scoped to function name)
- **Secrets Manager**: Read secrets (scoped to project/environment path)
- **CloudWatch Metrics**: Put custom metrics (scoped to GenesisAPI namespace)

**No wildcards** except where required by AWS API (e.g., GetAuthorizationToken for ECR).

## IAM Policy Simulation

To validate least-privilege permissions:

```bash
# Test Lambda role permissions
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::ACCOUNT_ID:role/genesis-api-dev-lambda-role \
  --action-names logs:CreateLogGroup logs:PutLogEvents \
  --resource-arns arn:aws:logs:us-east-1:ACCOUNT_ID:log-group:/aws/lambda/genesis-api-dev-*

# Test GitHub Actions role permissions  
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::ACCOUNT_ID:role/genesis-api-dev-github-actions-role \
  --action-names ecr:PutImage lambda:UpdateFunctionCode \
  --resource-arns arn:aws:lambda:us-east-1:ACCOUNT_ID:function:genesis-api-dev-*
```

## Resources Created

- 1x OIDC Provider (GitHub Actions)
- 2x IAM Roles (GitHub Actions, Lambda Execution)
- 4x IAM Role Policies (inline policies for least-privilege access)

## Tags

All resources are tagged with:
- **Name**: Resource-specific identifier
- **Environment**: Environment name (dev/prod/staging)
- **Project**: genesis-api
- **ManagedBy**: terragrunt
- **Owner**: Team/person responsible

## Dependencies

None - this module has no dependencies on other modules.

## Checkov Compliance

- ✅ OIDC provider has valid thumbprints
- ✅ IAM policies use least-privilege (no wildcards except ECR GetAuthorizationToken)
- ✅ IAM roles have trust policies with conditions
- ✅ All resources tagged

---

**Module Version**: 1.0.0  
**Last Updated**: April 11, 2026  
**Maintained By**: Pallab Paul
