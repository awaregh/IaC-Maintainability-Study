# IaC Maintainability: Engineering Recommendations

This document provides actionable guidance for engineering teams selecting a Terraform organizational strategy. Recommendations are based on the empirical findings in [`findings.md`](findings.md) and the patterns studied in this repository.

---

## 1. Choosing a Module Pattern

### 1.1 Decision Framework

Use the following questions to select a pattern:

| Question | If Yes → Consider | If No → Consider |
|---|---|---|
| Is this a small team (<5 engineers) managing a single service? | Monolithic or Small Composable | Domain-Based or higher |
| Do multiple teams own different parts of the infrastructure? | Domain-Based | Small Composable |
| Does the org have mature GitOps/CI pipelines with automated apply? | Layer-Based or State-Per-Stack | Domain-Based max |
| Is minimizing blast radius for regulatory/audit reasons critical? | State-Per-Stack | Domain-Based |
| Is there a need to run dev/staging/prod from one codebase? | Workspace-Based (with caution) | Separate directories per env |

### 1.2 Pattern Selection Guide

**Use Monolithic when:**
- You are prototyping or building a proof-of-concept
- The total resource count is < 30
- The infrastructure is managed by one person or small team
- You plan to refactor to a modular pattern within 6 months
- **Warning:** Set a scope limit. Establish a "graduate to modules" trigger (e.g., >30 resources or >2 engineers).

**Use Small Composable when:**
- You are a platform team building reusable infrastructure modules
- Multiple applications will compose the same underlying components
- Your team values single-responsibility and clear module interfaces
- **Warning:** Variable threading overhead is real. Use a module registry to avoid duplicating module code across teams.

**Use Domain-Based when:**
- Your organization has separate app, data, and platform/infrastructure teams
- You want module boundaries to align with ownership and on-call rotation
- You need a significant improvement over monolithic without full operational complexity
- **Best for:** Most teams in the 10–100 resource range with 2–5 infrastructure engineers

**Use Layer-Based when:**
- You have a mature platform engineering team with CI/CD automation for Terraform
- The system has clear, stable separation between networking, compute, data, and security
- You need strong isolation for compliance reasons (e.g., SOC 2, PCI DSS)
- You are prepared to invest in pipeline automation for ordered layer deployments
- **Warning:** Requires 5+ sequential apply steps. Without automation, human error in ordering is common.

**Use Workspace-Based only when:**
- The ONLY thing that differs between environments is variable values (not resource structure)
- You need workspace-per-environment for cost tracking purposes
- **Warning:** Do NOT use workspace-based as a substitute for structural isolation. Blast radius is identical to monolithic. Consider workspace-based for *environment parameterization* on top of a small-composable or domain-based structure.

**Use State-Per-Stack when:**
- You require maximum isolation between infrastructure components
- You are operating at scale (>200 resources, >5 engineers)
- Your CI/CD pipeline is mature enough to handle multi-stack dependency ordering
- Regulatory requirements demand blast radius minimization
- **Warning:** Adds significant operational complexity. SSM Parameter Store (or similar) for cross-stack references creates a runtime dependency that can be difficult to debug.

---

## 2. Drift Mitigation Strategies

### 2.1 Automated Drift Detection

Implement scheduled `terraform plan` runs in CI/CD:

```yaml
# Example: GitHub Actions scheduled drift detection
name: Drift Detection
on:
  schedule:
    - cron: '*/30 * * * *'  # Every 30 minutes
  workflow_dispatch:

jobs:
  detect-drift:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "1.5.0"
      - name: Terraform Plan (Drift Check)
        run: |
          terraform init
          terraform plan -detailed-exitcode -no-color 2>&1 | tee plan.out
          if [ $? -eq 2 ]; then
            echo "DRIFT DETECTED" >> $GITHUB_STEP_SUMMARY
            # Notify on-call
            curl -X POST "$SLACK_WEBHOOK" -d '{"text":"Terraform drift detected in production"}'
          fi
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
```

### 2.2 Preventive Drift Controls

**Lock down manual changes with SCPs:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyManualECSChanges",
      "Effect": "Deny",
      "Action": [
        "ecs:UpdateService",
        "ecs:UpdateTaskSet"
      ],
      "Resource": "*",
      "Condition": {
        "StringNotEquals": {
          "aws:PrincipalArn": "arn:aws:iam::ACCOUNT_ID:role/terraform-pipeline-role"
        }
      }
    }
  ]
}
```

**Use AWS Config rules to detect unauthorized changes:**
```hcl
resource "aws_config_config_rule" "iam_no_wildcard" {
  name = "iam-policy-no-statements-with-admin-access"
  source {
    owner             = "AWS"
    source_identifier = "IAM_POLICY_NO_STATEMENTS_WITH_ADMIN_ACCESS"
  }
}
```

### 2.3 Pin All Versions

Every reference system should have explicit version pinning:
```hcl
# versions.tf
terraform {
  required_version = ">= 1.5.0, < 2.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.31.0"  # Pin to exact version in production
    }
  }
}
```

Commit `.terraform.lock.hcl` to version control and review provider version updates as PRs.

### 2.4 Data Source Pinning

Avoid volatile data sources in production:
```hcl
# BAD: returns different AMI IDs over time
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*"]
  }
}

# GOOD: explicit, reproducible
variable "ec2_ami_id" {
  description = "Pinned AMI ID - update manually after testing"
  type        = string
  default     = "ami-0c02fb55956c7d316"  # amzn2-ami-hvm-2.0.20231116, us-east-1
}
```

---

## 3. State Management Best Practices

### 3.1 Remote State Configuration

All environments must use remote state with locking:
```hcl
terraform {
  backend "s3" {
    bucket         = "my-company-tfstate"
    key            = "${var.environment}/${local.stack_name}/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "my-company-tfstate-lock"
    encrypt        = true
    
    # Enable state versioning for rollback
    # (set on the S3 bucket, not here)
  }
}
```

**S3 bucket configuration requirements:**
- Enable versioning (allows state rollback)
- Enable server-side encryption (KMS recommended)
- Block all public access
- Enable MFA delete for additional protection
- Set up replication to a second region (for disaster recovery)

### 3.2 State File Organization

Recommended state key naming conventions:

| Pattern | Key Format | Example |
|---|---|---|
| Monolithic | `{env}/terraform.tfstate` | `prod/terraform.tfstate` |
| Small Composable | `{env}/terraform.tfstate` | `prod/terraform.tfstate` |
| Layer-Based | `{env}/{layer}/terraform.tfstate` | `prod/network/terraform.tfstate` |
| State-Per-Stack | `{env}/{stack}/terraform.tfstate` | `prod/compute/terraform.tfstate` |
| Multi-Region | `{env}/{region}/{stack}/terraform.tfstate` | `prod/us-east-1/network/terraform.tfstate` |

### 3.3 State Locking

Always use DynamoDB locking. Create the table with this Terraform:
```hcl
resource "aws_dynamodb_table" "tfstate_lock" {
  name         = "company-tfstate-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = { Purpose = "Terraform state locking" }
}
```

### 3.4 State Backup and Disaster Recovery

```bash
# Backup state before destructive operations
aws s3 cp s3://bucket/key/terraform.tfstate \
  s3://backup-bucket/key/terraform.tfstate.$(date +%Y%m%d_%H%M%S)

# List state versions
aws s3api list-object-versions \
  --bucket bucket \
  --prefix key/terraform.tfstate

# Restore from version
aws s3api get-object \
  --bucket bucket \
  --key key/terraform.tfstate \
  --version-id VERSION_ID \
  terraform.tfstate.restored
```

---

## 4. CI/CD Integration Recommendations

### 4.1 Pipeline Stages

Every Terraform change should pass through:

```
PR Opened → Format Check → Validate → Plan → Security Scan → Manual Review → Apply
```

### 4.2 Recommended Pipeline Implementation

```yaml
stages:
  - name: terraform-fmt
    command: terraform fmt -check -recursive
    on_failure: block_merge

  - name: terraform-validate
    command: terraform validate
    on_failure: block_merge

  - name: terraform-plan
    command: terraform plan -out=plan.binary -no-color
    on_failure: block_merge
    artifacts: [plan.binary, plan.txt]

  - name: security-scan
    command: |
      # Run checkov, tfsec, or similar
      checkov -d . --framework terraform --output json > checkov_results.json
    on_failure: warn  # or block_merge for strict compliance

  - name: cost-estimate
    command: infracost breakdown --path=plan.binary
    on_failure: warn

  - name: human-review
    type: manual_approval
    required_approvers: 1

  - name: terraform-apply
    command: terraform apply plan.binary
    on_failure: page_oncall
    environment: production
```

### 4.3 Environment Promotion Strategy

For layer-based and state-per-stack patterns:
```bash
# Apply layers in order with dependency checks
apply_with_deps() {
  local layers=("network" "security" "data" "compute" "observability")
  for layer in "${layers[@]}"; do
    echo "Applying $layer layer..."
    (cd "layers/$layer" && terraform init && terraform apply -auto-approve)
    if [[ $? -ne 0 ]]; then
      echo "ERROR: $layer layer apply failed. Stopping."
      exit 1
    fi
    echo "$layer layer applied successfully"
  done
}
```

### 4.4 Blast Radius Limits in CI

Implement guardrails to prevent large blast-radius changes from being applied automatically:
```bash
# Check blast radius before allowing auto-apply
MAX_AUTO_APPLY_CHANGES=10

PLAN_CHANGES=$(terraform show -json plan.binary | \
  jq '[.resource_changes[] | select(.change.actions != ["no-op"])] | length')

if [[ $PLAN_CHANGES -gt $MAX_AUTO_APPLY_CHANGES ]]; then
  echo "ERROR: Plan has $PLAN_CHANGES changes (max $MAX_AUTO_APPLY_CHANGES for auto-apply)"
  echo "This change requires manual review and approval"
  exit 1
fi
```

---

## 5. Migration Paths

### 5.1 Monolithic → Small Composable

```bash
# Step 1: Extract module code (don't change resources)
mkdir -p modules/vpc
cp main.tf modules/vpc/main.tf  # Copy only VPC resources
# Edit modules/vpc/main.tf to remove non-VPC resources

# Step 2: Add variables and outputs to module
# modules/vpc/variables.tf, modules/vpc/outputs.tf

# Step 3: Replace root module resources with module call
# main.tf: replace aws_vpc.* with module "vpc" { source = "./modules/vpc" }

# Step 4: Use terraform state mv to update state without destroying resources
terraform state mv aws_vpc.main module.vpc.aws_vpc.this
terraform state mv aws_subnet.public[0] 'module.vpc.aws_subnet.public[0]'
# ... repeat for all moved resources

# Step 5: Verify plan shows no changes
terraform plan  # Should show 0 changes if done correctly
```

### 5.2 Small Composable → Domain-Based

Combine related modules and update state references:
```bash
# Combine ecs + iam modules into app module
# Combine rds + s3 modules into data module
# Combine vpc + monitoring modules into platform module

# Use terraform state mv for each resource
terraform state mv module.ecs.aws_ecs_cluster.this module.app.aws_ecs_cluster.this
```

---

## Summary Recommendation Matrix

| Team Size | Resource Count | Recommended Pattern | Notes |
|---|---|---|---|
| 1-2 | < 30 | Monolithic | Set migration trigger at 30 resources |
| 1-3 | 30-100 | Small Composable | Good balance, low overhead |
| 2-5 | 50-200 | Domain-Based | Aligns with team ownership |
| 5-10 | 100-500 | Domain-Based or Layer-Based | Depends on pipeline maturity |
| 10+ | 200+ | Layer-Based or State-Per-Stack | Requires CI/CD investment |
| Any | Any | **Avoid Workspace-Based for isolation** | Use only for env parameterization |
