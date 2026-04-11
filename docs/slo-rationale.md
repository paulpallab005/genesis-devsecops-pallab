# SLO Target Rationale - Genesis Events API

## Overview

This document explains the rationale behind the 99.5% availability SLO target for the Genesis Events API, defines burn rate in operational terms, and outlines what would change after one month of production data.

---

## 1. Why 99.5% Availability?

The 99.5% SLO target was chosen based on **actual operational constraints** and **business context**, not arbitrary benchmarks.

### Data-Informed Decision Factors

**Service Classification**: The Genesis Events API is an **internal operations tool** used by the platform team for event tracking and operational workflows. It is NOT a customer-facing SaaS product. This distinction is critical:
- Customer-facing APIs typically require 99.9% or higher (max 43 minutes/month downtime)
- Internal tools can tolerate slightly more variance (99.5% = 216 minutes/month)

**AWS Lambda Baseline Performance**: Based on AWS Lambda service level agreements and observed reliability patterns:
- AWS publishes ~99.95% availability for Lambda in us-east-1
- After accounting for cold starts, transient errors, and application-level failures, a realistic achievable target for a new service is 99.5-99.7%
- Setting 99.9% on day one would result in constant SLO violations during the learning phase

**Development Environment Context**: This SLO applies to the **dev environment** specifically. Production would use a stricter target:
- Dev: 99.5% (allows experimentation, rapid iteration, acceptable brief outages)
- Prod: 99.9% (customer-impacting, stricter change control)

**Error Budget Math**:
```
(1 - 0.995) × 30 days × 24 hours × 60 minutes = 216 minutes per month
```
This gives us **3.6 hours of allowed downtime** or **~7 minutes per day** on average. This is:
- Enough tolerance for weekly deployments with brief unavailability
- Enough headroom for occasional Lambda cold start spikes
- Strict enough to catch systemic issues (persistent 5% error rate exhausts budget in 10 days)

**Real Traffic Patterns** (projected based on similar internal tools):
- Average: ~50 requests/hour during business hours
- Peak: ~200 requests/hour during deployment windows
- At 5% error rate sustained, that's 2.5-10 failing requests per hour
- Over 24 hours: 60-240 errors, consuming ~14 hours of error budget (6.5% of monthly allocation)
- This burn rate is **detectable within hours**, not days

### What This Target Enables

- **Rapid deployment cadence**: Multiple deploys per week without SLO anxiety
- **Experimental features**: Can test new code paths that might have higher initial error rates
- **Learning from failures**: Realistic target allows learning what "good" baseline looks like before tightening
- **Operational breathing room**: Maintenance windows, infrastructure changes won't immediately violate SLO

---

## 2. Burn Rate: Explained for Engineers

**Core Concept**: Burn rate measures **how fast you're consuming your error budget** compared to the normal rate.

### The Math

**Normal burn rate = 1.0**:
- You consume your 216-minute error budget evenly over 30 days
- Average: 7.2 minutes of errors per day
- This corresponds to your SLO target (0.5% error rate)

**Burn rate = 5.0** (our alert threshold):
- You're consuming error budget **5 times faster** than planned
- Instead of 7.2 minutes/day, you're burning ~36 minutes/day
- At this rate, your entire monthly budget is exhausted in **6 days** instead of 30

### Why Burn Rate > Static Thresholds

**Static threshold alarm**:
```
if error_rate > 5% for 5 minutes:
  alert("High error rate!")
```

**Problem**: This fires when error rate exceeds 5%, regardless of:
- How long it persists
- Whether it's a brief spike or sustained issue
- How much budget you've already consumed this month

**Burn rate alarm**:
```
if (actual_error_rate / allowed_error_rate) > 5 for 15 minutes:
  alert("Burning error budget 5× too fast!")
```

**Advantage**: This fires when you're consuming budget dangerously fast relative to your SLO commitment.

### Real-World Scenarios

**Scenario A - Brief Spike (Low Concern)**:
- Error rate: 10% for 5 minutes
- Static alarm: FIRES (error rate > 5%)
- Burn rate: 20× for 5 min, but drops to 1× after
- Result: Brief alert, low burn rate over 1 hour window → no escalation needed

**Scenario B - Sustained Degradation (High Concern)**:
- Error rate: 2.5% sustained over 3 hours
- Static alarm: DOES NOT FIRE (below 5% threshold)
- Burn rate: 5× sustained → consuming 50% of budget in 3 days instead of 15
- Result: Burn rate alert FIRES correctly, team investigates before budget exhausted

### What the On-Call Should Do

When paged for high burn rate:

1. **Check current error rate**: Is it a spike or sustained?
2. **Check CloudWatch Logs**: What's the error pattern? Same endpoint? Same error type?
3. **Check recent deployments**: Did error rate increase after a deploy?
4. **Estimate time to budget exhaustion**: At current burn rate, how many hours until 100% consumed?
5. **Decide on mitigation**:
   - If <6 hours to exhaustion: Consider rollback immediately
   - If 6-24 hours: Investigate root cause, prepare hotfix
   - If >24 hours but sustained: Schedule fix for next business day, monitor closely

---

## 3. What Would Change After One Month of Production Data?

### Measurement Adjustments

**Baseline Refinement**:
After 30 days, we'd have actual P50, P90, P99 error rates. If we observe:
- Actual error rate: 0.1-0.3% consistently → **Tighten SLO to 99.7% or 99.9%**
- Actual error rate: 1-2% with frequent spikes → **Keep 99.5% or relax to 99.0%**, investigate spikes

**Burn Rate Thresholding**:
- Current: Alert at 5× burn rate
- After 30 days: Might adjust to 3× if spikes are rare, or 10× if spikes are normal (e.g., cold starts)

### Traffic Pattern Exclusions

**Low Traffic Periods**:
If overnight traffic drops to <5 requests/hour, error rate becomes noisy (one error = 20% error rate). We'd exclude:
- Hours with <10 requests from SLO calculation
- Or weight errors by request volume (high-traffic errors cost more budget)

**Deployment Windows**:
If deployments consistently cause 2-3 minute error spikes (Lambda updates, container pulls), we'd:
- Exclude first 5 minutes post-deploy from SLO
- Or switch to blue-green deployment to eliminate spike

### SLI Refinement

**Current SLI**: Simple `(successful / total) × 100`

**After 30 Days**: Might add latency to SLI:
```yaml
sli:
  availability: (successful / total) × 100 >= 99.5%
  latency: P99 duration < 500ms for 99% of windows
```

This catches "slow = broken" scenarios where requests succeed but take >2 seconds (user perceives as failure).

### Error Budget Policy Tuning

**50% Budget Threshold**:
- Current: Informational Slack alert
- After 30 days: If we've never hit 50%, might remove this tier (too conservative)
- If we hit 50% monthly: Keep it, but add autoscaling or circuit breaker activation

**100% Budget Exhaustion**:
- Current: Hard deployment freeze
- After 30 days: Might change to "freeze feature deploys but allow hotfixes" if we have good rollback discipline

### Alerting Noise Reduction

**False Positive Patterns**:
If we see alerts for:
- Cold starts causing brief error spikes → Add cold start mitigation (provisioned concurrency)
- Specific Lambda timeout errors → Increase timeout or optimize code
- Downstream dependency failures → Add retry logic with exponential backoff

**Alert Fatigue Prevention**:
After 30 days, we'd measure:
- Alert precision: What % of alerts led to actual incidents?
- Alert recall: What % of incidents were caught by alerts?
- Target: >80% precision (low false positives), >95% recall (catch all real issues)

### What We'd Watch For

1. **Steady Trend**: Error rate decreasing over time as bugs fixed → Safe to tighten SLO
2. **Weekly Pattern**: Higher errors on Fridays (pre-weekend deploys) → Change deploy schedule
3. **Monthly Pattern**: First week of month has higher errors (new features) → Staged rollout
4. **Dependency Correlation**: Errors spike when external API is slow → Add circuit breaker

---

## Conclusion

The 99.5% SLO is a **starting point grounded in pragmatism**, not perfection. It gives us:
- Room to learn what "normal" looks like for this service
- Enough strictness to catch real problems before users notice
- Flexibility to iterate rapidly without constant SLO violations

After one month of data, we'll have the evidence needed to either **tighten the target** (if we're exceeding it easily) or **adjust the measurement approach** (if the current SLI doesn't capture real user pain).

The burn rate concept ensures we're alerted when error budget consumption accelerates dangerously, preventing the "slow leak" scenario where we gradually degrade without noticing until the budget is gone.

---

**Document Version**: 1.0  
**Last Updated**: April 11, 2026  
**Author**: Pallab Paul  
**Next Review**: After 30 days of production traffic (May 11, 2026)
