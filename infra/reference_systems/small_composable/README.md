# Reference System: Small Composable

The infrastructure is broken into six service-level modules, each encapsulating one AWS service domain.

## Structure

```
small_composable/
├── main.tf               # Root: calls all 6 modules
├── variables.tf
├── outputs.tf
├── versions.tf
└── modules/
    ├── vpc/              # VPC, subnets, NAT gateways, routing
    ├── ecs/              # ECS cluster, service, ALB, task definition
    ├── rds/              # RDS PostgreSQL instance and parameter group
    ├── s3/               # S3 bucket with versioning and encryption
    ├── iam/              # IAM roles and policies for ECS
    └── monitoring/       # CloudWatch alarms, SNS, dashboard
```

## Usage

```bash
cd infra/reference_systems/small_composable
terraform init
terraform plan -var="db_password=secret123"
terraform apply -var="db_password=secret123"
```

## Metrics (from study)

| Metric | Value |
|---|---|
| Total LOC | 2,134 |
| Module count | 6 |
| Coupling score | 1.08 |
| Reuse ratio | 0.87 |
| Blast radius | ~8 resources |
