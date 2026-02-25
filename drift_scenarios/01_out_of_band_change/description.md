# Drift Scenario 01: Out-of-Band Change

## Summary
Simulates a manual change made directly to AWS resources without updating Terraform code or state.

## Steps
1. The reference system is applied (ECS service running).
2. An operator manually updates the ECS service's desired task count via AWS CLI.
3. `terraform plan` is run — it detects the desired count mismatch and shows an update.

## What Terraform Detects
- `aws_ecs_service.app`: `desired_count` changed from `2` to `1` (or whatever the manual change was)

## Blast Radius Classification
- **Monolithic / Workspace**: HIGH — entire state file replanned
- **Small Composable / Domain-Based**: LOW — only ECS module is replanned
- **Layer-Based / State-Per-Stack**: LOW — only compute stack replanned

## Notes
This is the most common drift vector in production. Organizations without automated drift detection may not discover this change for days or weeks.
