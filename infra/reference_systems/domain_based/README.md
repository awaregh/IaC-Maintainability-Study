# Reference System: Domain-Based

Infrastructure grouped by business domain: app, data, platform.

## Structure

```
domain_based/
├── main.tf             # Root: calls 3 domain modules
├── variables.tf
├── outputs.tf
├── versions.tf
└── modules/
    ├── app/            # ECS Fargate service + IAM roles
    ├── data/           # RDS PostgreSQL + S3 bucket
    └── platform/       # VPC networking + SNS for monitoring
```

## Module Boundaries

- **app**: Owned by application team; ECS service, ALB, task definition, app IAM roles
- **data**: Owned by data team; RDS, S3, data-tier security groups
- **platform**: Owned by platform team; VPC, subnets, NAT gateways, shared SNS

## Usage

```bash
cd infra/reference_systems/domain_based
terraform init
terraform plan -var="db_password=secret123"
terraform apply -var="db_password=secret123"
```

## Metrics (from study)

| Metric | Value |
|---|---|
| Total LOC | 1,923 |
| Module count | 3 |
| Coupling score | 1.44 |
| Reuse ratio | 0.76 |
| Blast radius | ~19 resources |
