# Reference System: State-Per-Stack

Five independent stacks with separate state files. Cross-stack references use AWS SSM Parameter Store.

## Structure

```
state_per_stack/
└── stacks/
    ├── network/        # VPC — publishes VPC IDs to SSM
    ├── security/       # IAM + SGs — reads VPC from SSM, publishes role ARNs
    ├── data/           # RDS + S3 — reads from SSM, publishes endpoints
    ├── compute/        # ECS + ALB — reads all prior from SSM
    └── observability/  # CloudWatch — reads compute/data from SSM
```

## Deployment Order

```bash
for stack in network security data compute observability; do
  cd stacks/$stack
  terraform init
  terraform apply -auto-approve -var="db_password=secret123"
  cd ../..
done
```

## Cross-Stack References

Unlike layer-based (which uses `terraform_remote_state`), this pattern uses **AWS SSM Parameter Store** for cross-stack references. This means:
- No Terraform state-level dependency between stacks
- Cross-stack values are resolved at runtime (not plan time)
- Easier to use with different Terraform versions per stack

## Metrics (from study)

| Metric | Value |
|---|---|
| Total LOC | 2,287 |
| Module count | 5 stacks |
| Coupling score | 0.94 |
| Reuse ratio | 0.79 |
| Blast radius | ~7 resources |
