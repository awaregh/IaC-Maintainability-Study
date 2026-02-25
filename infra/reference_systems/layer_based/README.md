# Reference System: Layer-Based

Infrastructure divided into five independent stacks with remote state dependencies.

## Structure

```
layer_based/
├── layers/
│   ├── network/        # VPC, subnets, routing — deployed FIRST
│   ├── security/       # IAM roles, security groups — reads network state
│   ├── data/           # RDS, S3 — reads network + security state
│   ├── compute/        # ECS, ALB — reads network + security + data state
│   └── observability/  # CloudWatch, SNS — reads compute + data state
└── root/               # Documentation/orchestration helper
```

## Deployment Order

**Layers MUST be deployed in this order:**

```bash
for layer in network security data compute observability; do
  cd layers/$layer
  terraform init
  terraform apply -auto-approve
  cd ../..
done
```

## Cross-Layer Communication

Each layer reads outputs from prior layers via `terraform_remote_state` data sources pointing to S3 backend keys.

## Metrics (from study)

| Metric | Value |
|---|---|
| Total LOC | 2,301 |
| Module count | 5 layers |
| Coupling score | 1.12 |
| Reuse ratio | 0.82 |
| Blast radius | ~9 resources |
