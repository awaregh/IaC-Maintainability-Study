# Drift Scenario 03: Provider Default Drift

## Summary
Simulates a drift scenario where a cloud provider API default value changes, causing
terraform plan to show unexpected updates on resources that were not touched.

## Example: S3 Bucket Ownership Controls
AWS changed the default ACL ownership model for S3 buckets in 2023.
The Terraform AWS provider v4.x and v5.x handle bucket ownership differently.
Upgrading the provider without updating Terraform code results in plan showing
`aws_s3_bucket_ownership_controls` needing to be created.

## Detection Method
Run `terraform plan` after provider upgrade and inspect for updates to resources
that have not been changed in code.

## Blast Radius
Usually scoped to the specific resource type with the changed default.
In monolithic configs, the entire state is re-evaluated making signal hard to isolate.
