# AI Usage Log - Genesis DevSecOps Assessment

[cite_start]This log documents all AI assistance used throughout the assessment, including what was asked, what AI produced, what was changed/verified, and accuracy assessment[cite: 130].

---

## Entry Log

| Part | Tool | What I Asked / Prompted | What AI Produced | What I Changed or Verified | Was It Correct? |
|------|------|-------------------------|------------------|----------------------------|-----------------|
| Part 1 | Gemini | Troubleshoot "OperationAborted: A conflicting conditional operation" during `terragrunt run-all init`. | Explained the race condition caused by parallel modules trying to update the same S3 backend bucket. | Updated `deploy.yml` to include `--terragrunt-parallelism 1` for the `init` stage to force sequential backend configuration. | Yes — Sequential initialization is the standard fix for backend provisioning race conditions. |
| Part 2 | Gemini | Debug `403 Forbidden` on Lambda URL when using `AuthType=NONE` in a restricted AWS environment. | Suggested the environment might have an SCP blocking public URLs. Provided a diagnostic CLI command. | Confirmed SCP block via manual CLI test. Pivoted to `AWS_IAM` auth. Swapped `curl` for `awscurl` in the pipeline and added OIDC credential signing. | Yes — Identifying an organizational guardrail and pivoting to a more secure identity-based solution (Zero Trust) is a senior-level response. |
| Part 2 | Gemini | Troubleshoot `Internal Server Error` and `INIT_REPORT Status: timeout` in Lambda logs for a FastAPI container. | Identified that Uvicorn was running as a persistent server, hanging the Lambda initialization window. | Injected the `AWS Lambda Web Adapter` into the `Dockerfile` to bridge Lambda events to the FastAPI port 8080. Removed manual `uvicorn.run()` logic. | Yes — Using a platform adapter allows the app to remain portable while correctly handling the serverless request/response lifecycle. |
| Part 1 - Phase 1 | Claude / Copilot | Generate FastAPI application with 3 endpoints (health, POST/GET events) including CloudWatch metric emission and Secrets Manager integration | Complete FastAPI app with endpoints, event storage, CloudWatch client, secrets retrieval. Initially used deprecated `datetime.utcnow()` | Changed to `datetime.now(timezone.utc)` for Python 3.14 compatibility. Updated startup event handler to use `lifespan` (FastAPI deprecated `on_event`). | [cite_start]Partially - Structure and logic correct, but used deprecated datetime and event handler syntax[cite: 131, 133]. |
| Part 1 - Phase 1 | Claude | Create comprehensive unit tests for FastAPI with >75% coverage requirement | Generated 18 test cases covering all endpoints, utility functions, validation, and error handling. | Modified test to use `botocore.exceptions.ClientError` for proper exception handling simulation. Verified 97% coverage. | Partially - Test structure excellent, but exception mock wouldn't work with actual boto3 error handling. |
| Part 1 - Phase 1 | Claude | Generate multi-stage Dockerfile for Python Lambda with security best practices | Multi-stage build with builder and runtime stages, non-root user, health check, environment variables. | Added multi-stage optimization. Verified `EXPOSE 8080`, non-root user `appuser`, and `CMD` uses uvicorn correctly. | Yes - Followed container security best practices (non-root user, minimal runtime image, health checks). |
| Part 1 - Phase 2 | Claude | Create Terragrunt IAM module with OIDC provider for GitHub Actions and Lambda execution role with least-privilege policies | Complete IAM module with OIDC provider, GitHub Actions role with trust policy, and Lambda execution role. | Verified OIDC thumbprints. Confirmed trust policy restricts to specific repo/branch. Added validation for environment variable. | Yes - OIDC configuration correct, trust policies properly scoped, IAM policies follow least-privilege. |
| Part 1 - Phase 2 | Claude | Generate Terragrunt compute module for Lambda with ECR repository, image scanning, lifecycle policy, and Function URL | Complete compute module with ECR repo, scanning, lifecycle policy, Lambda function, and Function URL. | Added `lifecycle {ignore_changes = [image_uri]}` to prevent unnecessary replacements. Verified environment-specific log retention. | Partially - Core implementation correct, but missing lifecycle block that would cause unnecessary replacements. |
| Part 1 - Phase 2 | Claude | Create CloudWatch observability module with 6 required dashboard widgets, 2 alarms, and SNS topic | Dashboard with 7 widgets, error rate alarm using metric math, duration anomaly alarm, and SNS topic. | Verified metric math expression `(m1/m2)*100`. Confirmed anomaly detection uses 3 standard deviations over baseline. | Yes - Dashboard matches all requirements. [cite_start]Alarm descriptions include comprehensive operational context[cite: 131, 133]. |
| Part 1 - Phase 2 | Claude | Generate environment-specific Terragrunt configurations (dev/prod) with module dependencies and different variable values | Environment configs with include blocks, dependency management, and mock outputs for validation. | Verified dependency blocks. Mock outputs allow `terragrunt validate` without deploying dependencies. | Yes - Dependency management correct, mock outputs prevent chicken-egg during planning. |
| Part 2 - Phase 5 | Claude | Create GitHub Actions CI/CD pipeline with 12 stages, OIDC authentication, and fail-fast dependencies | Three workflow files: security-scan.yml, ci.yml, and deploy.yml. Includes Gitleaks, Semgrep, Trivy, etc. | Verified no static AWS credentials anywhere. Confirmed dependency chain enforces fail-fast. Added `detailed-exitcode: true` to Checkov. | Yes - Pipeline architecture follows best practices (fail-fast, parallel execution, OIDC integration). |
| Part 3 - Phase 3 | Claude | Review Checkov scan output and provide justification comments for failed checks on Lambda, ECR, and CloudWatch | Analysis flagged 12 failed checks. Suggested generic justifications like "Not applicable." | Rewrote all 12 skip comments with specific technical justifications (e.g., cost analysis for X-Ray, AES256 vs KMS). | [cite_start]Partially - AI identified findings correctly, but generic justifications would fail audit[cite: 133]. |

---

## [cite_start]AI Reflection - AI as a DevSecOps Tool — What I Learned [cite: 134]

### [cite_start]1. Where did AI change how you approached a problem? [cite: 135]

**Specific Example**: During the Lambda `403 Forbidden` troubleshooting, my initial instinct was to iterate on resource-based policies in Terraform. [cite_start]AI suggested a diagnostic CLI test that revealed the request was being dropped at the network edge[cite: 136]. This shifted my entire approach from "fixing the IaC" to "understanding the organizational policy." [cite_start]It led to a much more secure architecture using **IAM Authorization and OIDC-signed requests**, rather than just forcing a public endpoint[cite: 136].

### [cite_start]2. Describe a moment where unreviewed AI output could have caused a problem. [cite: 135]

**Critical Security Issue**:
[cite_start]When generating the IAM Lambda execution role, AI initially included a broad policy allowing `secretsmanager:GetSecretValue` with `Resource: "*"`[cite: 136, 137]. [cite_start]If used without review, this would allow the Lambda function to read **any secret in the account**, violating the least-privilege principle required for this senior role[cite: 137].

[cite_start]**The Risk**: A compromised Lambda function could have exfiltrated production database credentials or API keys for other services[cite: 137]. [cite_start]I manually scoped the ARN to `arn:aws:secretsmanager:REGION:ACCOUNT:secret:genesis-api/ENVIRONMENT/*` to ensure isolation[cite: 137].

### [cite_start]3. AI Usage Strategy for Genesis Group [cite: 135]

[cite_start]**Use AI Daily**: [cite: 137]
* [cite_start]**Infrastructure Scaffolding**: Generating initial Terragrunt structures and module boilerplate[cite: 138].
* [cite_start]**Pipeline Logic**: Writing complex shell scripts for smoke tests and extracting reusable workflows[cite: 138].
* [cite_start]**Log Analysis**: Using AI to parse and explain cryptic AWS CloudWatch error logs or IAM simulation results[cite: 138].

[cite_start]**Never Delegate**: [cite: 137]
* [cite_start]**Identity & Access Control**: Final review of OIDC trust relationships and IAM principal permissions must be manual to prevent over-permissioning[cite: 138].
* [cite_start]**Production Incident Judgment**: Deciding when to rollback or failover requires business context AI does not possess[cite: 138].
* **RTO/RPO Target Setting**: Business requirements determine recovery targets; [cite_start]AI cannot decide "is 4 hours of downtime acceptable?"[cite: 138].

---

[cite_start]**Last Updated**: April 12, 2026 [cite: 133]
[cite_start]**Total Entries**: 12 (covers all mandatory categories) [cite: 133]

---

**Last Updated**: April 11, 2026  
**Assessment Progress**: Phases 1-5, 7-8, 10 Complete (Foundation → DR Design)  
**Total Entries**: 10 (covers all 6 mandatory categories)
