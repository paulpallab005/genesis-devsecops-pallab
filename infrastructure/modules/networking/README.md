# Networking Module

This module is a placeholder for VPC networking configuration. Currently, the Lambda function uses AWS's default execution environment without VPC configuration.

## Purpose

For the assessment, Lambda runs without VPC attachment to simplify architecture and avoid NAT Gateway costs. This module exists to maintain structural consistency and can be extended for production VPC requirements.

## Current Implementation

**No resources created** - Lambda uses AWS default networking:
- No VPC attachment
- No subnets or route tables
- No NAT Gateway or Internet Gateway
- No security groups

## Future Production Requirements

For production deployment with VPC:

```hcl
# Example VPC configuration (not implemented)
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.${count.index + 1}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]
}

resource "aws_nat_gateway" "main" {
  # Required for Lambda to access internet from private subnet
}

resource "aws_security_group" "lambda" {
  vpc_id = aws_vpc.main.id
  # Egress rules for Lambda
}
```

## Why No VPC for Assessment?

1. **Cost**: NAT Gateway costs ~$32/month (exceeds free tier)
2. **Simplicity**: Lambda Function URL works without VPC
3. **No Private Resources**: No RDS, ElastiCache, or private APIs to access
4. **Internet Access**: Lambda needs internet for Secrets Manager, CloudWatch - VPC requires NAT

## Production Considerations

When to add VPC:
- **Database Access**: RDS instances in private subnets
- **Private APIs**: Internal services not exposed to internet
- **Compliance**: PCI-DSS or HIPAA requirements for network isolation
- **IP Whitelisting**: Fixed IP addresses via NAT Gateway for third-party APIs

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| aws_region | AWS region | string | us-east-1 | no |
| environment | Environment name | string | - | yes |
| project | Project name | string | genesis-api | no |
| owner | Owner name | string | pallab | no |

## Outputs

| Name | Description | Value |
|------|-------------|-------|
| vpc_id | VPC ID | null (no VPC) |
| private_subnet_ids | Private subnet IDs | [] (empty) |
| security_group_id | Security group ID | null (no SG) |

## Dependencies

None - this module has no dependencies.

## Resources Created

None - placeholder module.

---

**Module Version**: 1.0.0  
**Last Updated**: April 11, 2026  
**Maintained By**: Pallab Paul
