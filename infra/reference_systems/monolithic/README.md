# Reference System: Monolithic

All 60+ resources are defined in a single root module (`main.tf`).

## Structure

```
monolithic/
├── main.tf       # All resources: VPC, ECS, RDS, S3, IAM, CloudWatch
├── variables.tf
├── outputs.tf
└── versions.tf
```

## Usage

```bash
cd infra/reference_systems/monolithic

# Initialize
terraform init

# Plan
terraform plan -var="db_password=secret123"

# Apply
terraform apply -var="db_password=secret123"

# Destroy
terraform destroy -var="db_password=secret123"
```

## Metrics (from study)

| Metric | Value |
|---|---|
| Total LOC | 1,847 |
| Resource blocks | 48 |
| Module count | 0 |
| Coupling score | 3.21 |
| Reuse ratio | 0.00 |
| Blast radius | 52 resources |

## Tradeoffs

- ✅ Simple to understand initially
- ✅ No interface overhead
- ❌ High coupling (3.21 E/N ratio)
- ❌ Large blast radius (all 48 resources in every plan)
- ❌ Does not scale beyond ~30 resources
