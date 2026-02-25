# Drift Scenario 06: IAM / Config Drift

## Summary
Simulates unauthorized or untracked changes to IAM policies and role configurations.
This is one of the most security-critical drift types, as IAM changes can expand
attack surface or break application functionality.

## Drift Mechanisms
1. **Policy expansion**: An IAM policy is broadened (e.g., `s3:*` instead of specific actions)
2. **Trust relationship change**: A new principal is added to a role's trust policy
3. **Resource tag removal**: Tags used for ABAC policies are removed
4. **Permission boundary removal**: Boundaries restricting elevated permissions are removed

## Detection Method
- `terraform plan` shows changes to `aws_iam_role_policy` or `aws_iam_role` resources
- AWS CloudTrail: query for `PutRolePolicy`, `UpdateAssumeRolePolicy` events
- AWS Config rule: check `iam-policy-no-statements-with-admin-access`

## Blast Radius
- Security blast radius: CRITICAL (potential privilege escalation)
- Terraform blast radius: LOW (only IAM resources affected in modular configs)
  but HIGH in monolithic configs (entire state replanned)
