# Reference System: Workspace-Based

Single codebase using `terraform.workspace` to parameterize environment-specific configuration.

## Structure

```
workspace_based/
├── main.tf         # All resources; env config via local.env_config[workspace]
├── variables.tf    # Minimal variables (only secrets/overrides)
├── outputs.tf
├── versions.tf
└── envs/
    ├── dev.tfvars
    ├── staging.tfvars
    └── prod.tfvars
```

## Usage

```bash
cd infra/reference_systems/workspace_based

# Create and select workspace
terraform workspace new dev
terraform workspace select dev

# Apply with environment-specific vars
terraform init
terraform plan -var-file=envs/dev.tfvars
terraform apply -var-file=envs/dev.tfvars

# Switch to staging
terraform workspace select staging
terraform apply -var-file=envs/staging.tfvars
```

## ⚠️ Warning

**Workspace-based configurations provide NO structural isolation.** All resources share the same dependency graph. Blast radius is identical to monolithic (~49 resources). Use this pattern only for environment parameterization, not as a substitute for structural isolation.

## Metrics (from study)

| Metric | Value |
|---|---|
| Total LOC | 1,891 |
| Module count | 0 |
| Coupling score | 3.18 |
| Reuse ratio | 0.00 |
| Blast radius | ~49 resources |
