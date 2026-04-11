# AI Usage Log - Genesis DevSecOps Assessment

This log documents all AI assistance used throughout the assessment, including what was asked, what AI produced, what was changed/verified, and accuracy assessment.

---

## Entry Log

| Part | Tool | What I Asked / Prompted | What AI Produced | What I Changed or Verified | Was It Correct? |
|------|------|-------------------------|------------------|----------------------------|-----------------|
| Part 1 - Phase 1 | Claude / GitHub Copilot | Generate FastAPI application with 3 endpoints (health, POST/GET events) including CloudWatch metric emission and Secrets Manager integration | Complete FastAPI app with endpoints, event storage, CloudWatch client, secrets retrieval. Initially used deprecated `datetime.utcnow()` | Changed to `datetime.now(timezone.utc)` for Python 3.14 compatibility. Updated startup event handler to use `lifespan` (FastAPI deprecated `on_event`). Verified CloudWatch metric emission and secrets handling work correctly. | Partially - Structure and logic correct, but used deprecated datetime and event handler syntax that would fail in modern Python/FastAPI |
| Part 1 - Phase 1 | Claude | Create comprehensive unit tests for FastAPI with >75% coverage requirement | Generated 18 test cases covering all endpoints, utility functions, validation, error handling. Tests for secrets retrieval initially used generic Exception instead of ClientError | Modified test to use `botocore.exceptions.ClientError` for proper exception handling simulation. Verified all 18 tests pass with 97% coverage. | Partially - Test structure excellent, but exception mock wouldn't work with actual boto3 error handling |
| Part 1 - Phase 1 | Claude | Generate multi-stage Dockerfile for Python Lambda with security best practices | Multi-stage build with builder and runtime stages, non-root user, health check, environment variables | Added multi-stage optimization (copy from builder to slim runtime). Verified EXPOSE 8080, non-root user `appuser`, and CMD uses uvicorn correctly. No changes needed - ready for production. | Yes - Followed container security best practices (non-root user, minimal runtime image, health checks) |
| Part 1 - Phase 2 | Claude | Create Terragrunt IAM module with OIDC provider for GitHub Actions and Lambda execution role with least-privilege policies | Complete IAM module with OIDC provider, GitHub Actions role with trust policy, Lambda execution role, 4 inline policies scoped to specific resources | Verified OIDC thumbprints are current for GitHub, trust policy restricts to specific repo/branch via StringLike condition, Lambda policies scoped to log groups with function name prefix, Secrets Manager scoped to project/env path. Added validation for environment variable. | Yes - OIDC configuration correct, trust policies properly scoped, IAM policies follow least-privilege with resource-level permissions |
| Part 1 - Phase 2 | Claude | Generate Terragrunt compute module for Lambda with ECR repository, image scanning, lifecycle policy, and Function URL | Complete compute module with ECR repo, scanning enabled, lifecycle policy (keep 10 images), Lambda function with container image, Function URL with CORS, CloudWatch log group | Added `lifecycle {ignore_changes = [image_uri]}` to prevent Terraform replacement on every image update. Verified ECR encryption (AES256), image scanning on push, log retention differs by environment (7 days dev, 30 days prod). CORS wide open (*) - noted to restrict in production. | Partially - Core implementation correct, but missing lifecycle block that would cause unnecessary Lambda replacements. Security note about CORS needed. |
| Part 1 - Phase 2 | Claude | Create CloudWatch observability module with 6 required dashboard widgets, 2 alarms (error rate threshold + P99 anomaly), SNS topic | Dashboard with 7 widgets (6 required + 1 custom metric), error rate alarm using metric math, duration anomaly alarm with ANOMALY_DETECTION_BAND, SNS topic with KMS encryption, detailed alarm descriptions with runbook URLs | Verified metric math expression `(m1/m2)*100` for error rate calculation. Confirmed anomaly detection uses 3 standard deviations over 7-day baseline (relative threshold vs absolute). Alarm descriptions include operational context, troubleshooting steps, SLA, runbook URLs as required. SNS requires email confirmation post-deploy. | Yes - Dashboard configuration matches all requirements (invocations, error %, P50, P99, throttles, concurrent executions, custom metric). Alarm descriptions comprehensive with operational guidance. |
| Part 1 - Phase 2 | Claude | Generate environment-specific Terragrunt configurations (dev/prod) with module dependencies and different variable values | Environment configs with include blocks, dependency management (compute depends on IAM, observability depends on compute), mock outputs for validation/planning, environment-specific thresholds | Verified dependency blocks use correct config_path relative paths. Mock outputs allow `terragrunt validate` without deploying dependencies. Dev vs prod differences: memory (512 vs 1024), timeout (30 vs 60), error rate threshold (10% vs 5%), evaluation periods (1 vs 2). | Yes - Dependency management correct, mock outputs prevent chicken-egg during planning, environment differentiation shows production-grade thinking |
| Part 2 - Phase 5 | Claude | Create GitHub Actions CI/CD pipeline with 12 stages, OIDC authentication, reusable workflow pattern, fail-fast dependencies | Three workflow files: security-scan.yml (reusable, stages 1-4), ci.yml (PR pipeline, stages 1-10), deploy.yml (main branch, stages 11-12). Includes Gitleaks, pip-audit, Semgrep, Trivy, Syft, Cosign, tflint, Checkov. OIDC config with assume-role. | Verified no static AWS credentials anywhere (grep -r "AKIA" returned 0 matches). Confirmed dependency chain enforces fail-fast (security stages block build stages). Added `detailed-exitcode: true` to Checkov to fail on findings. Fixed artifact upload paths. Confirmed Cosign keyless signing works in PR context without push permission. | Yes - Pipeline architecture follows best practices (fail-fast, parallel execution, artifact retention policies, reusable workflow extraction). OIDC configuration matches IAM trust policy. |
| Part 3 - Phase 7 | Claude | Design SLO YAML with 99.5% availability target, error budget, burn rate thresholds, and CloudWatch Metrics Insights query | Complete SLO YAML with service definition, SLI calculation from CloudWatch metrics, 30-day SLO window, error budget (216 minutes calculated), burn rate threshold (5×), error budget policy (actions at 50%/75%/100%), Metrics Insights query, alert configuration | Verified error budget math: (1 - 0.995) × 30 days × 24 hours × 60 min = 216 min. Confirmed burn rate of 5× means alerting when consuming budget 5 times faster than normal (4.3 hours to exhaust vs 30 days). Adjusted policy actions to match Genesis Group operational practices (Slack → page → incident). | Yes - YAML structure matches industry standards (Google SRE workbook). Burn rate threshold of 5× balances noise reduction with early warning. Error budget policy provides graduated response preventing alert fatigue. |
| Part 3 - Phase 3 | Claude | Review Checkov scan output and provide justification comments for failed checks on Lambda, ECR, and CloudWatch resources | Initial analysis flagged 12 failed checks across compute and observability modules. Suggested generic justifications like "Not applicable for this use case" | Rewrote all 12 skip comments with specific technical justifications: ECR KMS encryption not needed (using AES256 for cost), Lambda X-Ray disabled due to free-tier limits with detailed cost analysis ($0.004/trace vs budget), DLQ skipped for testing OPA policy framework, Function URL authorization NONE acceptable for dev environment only, log group KMS encryption explained AWS-managed keys sufficient for internal tool. Added reference to Checkov docs for each CKV ID. | Partially - AI identified findings correctly, but generic justifications would fail audit. Required deep understanding of AWS service costs, security context, and acceptable risk for internal dev tools to write production-grade skip comments. |

---

## AI Reflection - AI as a DevSecOps Tool — What I Learned

### 1. Where did AI change how you approached a problem — not just accelerated it, but actually changed your approach?

**Specific Example**: When designing the CloudWatch alarm for P99 latency, I initially planned to use a static threshold (e.g., "P99 > 1000ms"). AI suggested using `ANOMALY_DETECTION_BAND` with a relative threshold based on 7-day rolling baseline and standard deviations. This fundamentally changed the approach:

- **Before**: Absolute threshold that might fire too early (when baseline is 300ms but spikes to 800ms) or too late (if baseline drifts to 1500ms gradually)
- **After**: Relative anomaly detection that adapts to normal variance and catches degradation early regardless of absolute values

This wasn't just faster implementation — it was a **better architectural decision** I wouldn't have considered. The metric math expression `ANOMALY_DETECTION_BAND(duration_p99, 3)` is more sophisticated than I typically use, and AI explained the operational benefit clearly.

### 2. Describe the moment in this assessment where AI output could have caused a security or reliability problem if you had used it without review. What was the output and what was the risk?

**Critical Security Issue**:  
When generating the IAM Lambda execution role, AI initially included a broad policy allowing `secretsmanager:GetSecretValue` with `Resource: "*"` (wildcard). If deployed as-is, this would allow the Lambda function to read **any secret in the account**, including production database credentials, API keys for other services, and encryption keys.

**The Risk**:
- Violates least-privilege principle (Part 1 requirement: 15 marks)
- If Lambda code is compromised (code injection, dependency vulnerability), attacker could exfiltrate all secrets
- Fails `aws iam simulate-principal-policy` review (Part 9 requirement)
- Checkov would flag this as CRITICAL finding

**What I Did**:
Changed the Resource ARN to:
```json
"Resource": "arn:aws:secretsmanager:REGION:ACCOUNT:secret:genesis-api/ENVIRONMENT/*"
```

This scopes secrets access to only the project/environment path (e.g., `genesis-api/dev/*`). A compromised dev Lambda cannot read prod secrets.

**Lesson**: AI optimizes for "working code," not necessarily "secure code." Always review IAM policies with the principle of least privilege as a mental checklist.

### 3. As a senior DevSecOps engineer at Genesis Group, where would you use AI day-to-day and where would you never delegate to it? Be specific — name the tasks in each category.

**Use AI Daily**:
1. **Boilerplate Infrastructure Code**: Generating initial Terraform modules with standard patterns (VPC, security groups, S3 buckets). Then customize for specific requirements.
2. **Refactoring Pipeline YAML**: Converting Jenkins pipelines to GitHub Actions, optimizing stage ordering, adding parallel execution.
3. **Documentation Generation**: Converting terraform-docs outputs into readable README files, creating runbooks from alarm descriptions.
4. **Regex and JMESPath Queries**: Building complex CloudWatch Logs Insights queries, jq filters for JSON processing.
5. **Test Case Generation**: Creating comprehensive test suites from API specs (like the 18 test cases for FastAPI endpoints).
6. **Security Scan Triage**: Explaining Checkov/Trivy findings and suggesting remediation (then verify remediation myself).

**Never Delegate to AI** (Requires Human Judgment):
1. **IAM Trust Policies & Permission Boundaries**: AI doesn't understand the full blast radius of overly permissive policies in a multi-account org. I review every `Resource: "*"` and justify it.
2. **Production Incident Response**: AI can suggest troubleshooting steps, but deciding to rollback, failover, or page on-call requires context AI doesn't have (customer impact, SLA status, change freeze windows).
3. **RTO/RPO Target Setting**: Business requirements (cost, compliance, customer expectations) determine recovery targets. AI can calculate downtime math, but can't decide "is 4 hours acceptable?"
4. **Secret Values & Credentials**: Never ask AI to generate actual passwords, API keys, or tokens. Use password managers or AWS Secrets Manager directly.
5. **Code Review for Production Merge**: AI can flag issues, but final approval for production deployment requires understanding of system state, recent incidents, and deployment risk that AI lacks.
6. **Compliance Decisions**: Determining if infrastructure meets PCI-DSS, HIPAA, or SOC 2 requirements needs auditor-level knowledge. AI can list controls, but can't certify compliance.

**The Pattern**: Use AI for **generation and acceleration**, but **always verify** security, reliability, and business alignment. AI is an L2 engineer who needs supervision, not a senior architect who sets strategy.

---

**Last Updated**: April 11, 2026  
**Assessment Progress**: Phases 1-5, 7-8, 10 Complete (Foundation → DR Design)  
**Total Entries**: 10 (covers all 6 mandatory categories)
