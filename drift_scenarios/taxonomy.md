# Drift Scenario Taxonomy

This document catalogs the six drift categories studied in the IaC Maintainability Study. Each category includes a description, representative example, detection method, and blast radius classification.

---

## Overview

Configuration drift in Terraform-managed infrastructure occurs when the actual state of resources diverges from the state declared in code and tracked in the Terraform state file. Drift can arise from human error, tooling changes, cloud provider evolution, or infrastructure failures.

We classify drift into six categories based on root cause and detection characteristics.

---

## Category 1: Out-of-Band Change

**Description:** A resource attribute is modified directly through the AWS console, CLI, SDK, or another automation tool without updating Terraform code or state. The next `terraform plan` detects the divergence because the live resource no longer matches the state file.

**Example:**
- An engineer manually modifies an ECS task definition via the AWS console to change the container image tag during an incident.
- An IAM policy is edited directly via `aws iam put-role-policy` without corresponding Terraform changes.
- An S3 bucket lifecycle rule is removed via the AWS console.

**Detection Method:** `terraform plan` compares the state file against the live resource description from the AWS API. Any attribute diff between planned and actual values triggers an `update` action in the plan.

**Blast Radius:** Depends on the resource affected. In monolithic/workspace configurations, the entire state file is re-evaluated, meaning dozens of resources appear in plan output even if only one drifted. In state-per-stack or layer-based configurations, only the relevant stack's plan is affected.

**Classification:** CRITICAL for production IAM, HIGH for compute/data, MEDIUM for monitoring

---

## Category 2: Version Drift

**Description:** A module version constraint in `required_providers` or a module `source` version is changed in one environment but not another, or a new provider minor version is released that changes default behavior of existing resources.

**Example:**
- `aws ~> 4.67` is pinned in dev but `aws ~> 5.0` is deployed in production after a provider upgrade.
- A community module at `github.com/org/module` is updated with a breaking change but the consuming configuration continues to reference the old version tag.
- `hashicorp/random` v3.4 generates different outputs than v3.5 for the same seed.

**Detection Method:** Run `terraform providers lock -upgrade` and diff the resulting `.terraform.lock.hcl` against the committed version. Also check provider version output in `terraform version`. Version drift in plan output appears as unexpected resource replacements.

**Blast Radius:** Can be HIGH to CRITICAL depending on which provider version changed and how many resources it manages. Provider major version bumps (e.g., AWS provider v4 → v5) can trigger replacement of resources that changed their schema.

**Classification:** HIGH (provider major version), MEDIUM (minor version), LOW (patch version)

---

## Category 3: Provider Default Drift

**Description:** AWS silently changes the default value of a resource attribute without changing the API schema. Because Terraform omits attributes that match the provider's default, a new default causes existing resources to appear out of compliance when the provider is upgraded.

**Example:**
- AWS changes the default value of `deletion_protection` for RDS from `false` to `true` in a provider release.
- The default encryption setting for new S3 buckets changes at the AWS service level, and the Terraform AWS provider updates its defaults to match.
- ECS task definition `network_mode` default changes between provider versions.

**Detection Method:** Running `terraform plan` after a provider upgrade surfaces unexpected `update` actions where no code changed. Diffing the plan JSON against a known-good baseline helps identify provider-default-driven changes.

**Blast Radius:** Can affect many resources of the same type simultaneously. In a monolithic configuration, a single provider default change can produce a plan with 20+ updates.

**Classification:** MEDIUM (monitoring drift), HIGH (security defaults like encryption)

---

## Category 4: Data Source Nondeterminism

**Description:** A `data` source in Terraform returns different results across plan invocations because the underlying AWS API returns different values (e.g., AMI IDs, availability zones, security group lists) depending on when the query is executed.

**Example:**
- `data "aws_ami" "amazon_linux"` queries for the most recent Amazon Linux 2 AMI; over time, new AMIs are released and the data source returns a different AMI ID.
- `data "aws_availability_zones" "available"` returns AZs in different order depending on API response, causing subnet count changes.
- `data "aws_security_groups"` with a filter query returns an extra security group added by a separate process.

**Detection Method:** The `terraform plan` output shows resource replacements or updates triggered by changed data source values. Pinning data source queries (e.g., using `most_recent = false` and a specific `filter`) or using fixed resource IDs instead of data sources reduces this risk.

**Blast Radius:** Usually LOW to MEDIUM in isolation, but can cascade. An AMI change triggers ECS task definition replacement, which triggers service redeployment.

**Classification:** LOW (informational data), MEDIUM (compute resources referencing AMI), HIGH (if data source feeds security configuration)

---

## Category 5: Partial Apply / State Issues

**Description:** A `terraform apply` is interrupted before completion (network failure, timeout, Ctrl+C, process kill), leaving some resources created/modified and others unchanged. The state file may partially reflect the new desired state, creating an inconsistent reality.

**Example:**
- An apply creating VPC + subnets + ECS cluster is interrupted after VPC creation but before subnet creation. The VPC exists in AWS and in state, but subnets do not. Subsequent plans detect the missing subnets.
- A `terraform destroy` is interrupted, leaving orphaned security groups that block subsequent applies.
- State file corruption from a concurrent apply (without DynamoDB locking) causes resource metadata to be incorrect.

**Detection Method:** `terraform plan` after a partial apply shows resources to create that should already exist, or resources with attributes inconsistent with the actual infrastructure. `terraform state list` can be diffed against actual AWS resource listings.

**Blast Radius:** HIGH to CRITICAL — partial state is unpredictable. In a monolithic configuration, a partial apply can affect all resources. State-per-stack architectures limit the blast radius to the affected stack.

**Classification:** HIGH (any partial apply), CRITICAL (state corruption)

---

## Category 6: IAM / Config Drift

**Description:** IAM policies, role trust relationships, or configuration values (e.g., resource tags, environment variables, parameter store values) drift from their Terraform-declared values due to manual changes, automated tooling, or AWS service behavior.

**Example:**
- A security scanning tool automatically adds a condition to an IAM role trust policy, which Terraform then wants to remove on the next apply.
- AWS Config remediation rules modify resource tags that Terraform manages, causing a perpetual tag drift loop.
- A Lambda function environment variable is updated via the AWS console to temporarily change application behavior; the Terraform definition still has the old value.
- KMS key policies are modified by a central security team's automation outside of Terraform.

**Detection Method:** `terraform plan` detects IAM/config drift as `update` actions. Automated drift detection pipelines that run `terraform plan` on a schedule (e.g., every 30 minutes) catch these changes quickly. AWS Config rules can also flag non-compliant resources.

**Blast Radius:** Varies widely. An IAM policy drift is typically LOW blast radius (one policy) but can be CRITICAL in terms of security impact. Tag drift across many resources creates noisy plans in monolithic configurations.

**Classification:** CRITICAL (IAM trust policies, access policies), HIGH (encryption configuration), LOW-MEDIUM (tags, non-security config)
