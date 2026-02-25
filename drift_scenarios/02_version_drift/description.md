# Drift Scenario 02: Version Drift

## Summary
Simulates version skew between the pinned provider version in dev and production.
The scenario modifies the `versions.tf` required_providers constraint and runs init with upgrade.

## Drift Mechanism
`versions.tf` is modified to use a newer provider version constraint, then `terraform init -upgrade`
is run. The resulting plan may show resource updates due to schema or default changes.

## Blast Radius
- All resources managed by the drifted provider
- HIGH for major version bumps (AWS provider v4→v5 changed many defaults)
- LOW for patch version bumps

## Detection Method
Compare `.terraform.lock.hcl` between environments.
Run `terraform providers lock -upgrade` and diff outputs.
