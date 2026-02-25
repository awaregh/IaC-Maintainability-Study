# Drift Scenario 04: Data Source Nondeterminism

## Summary
Simulates the behavior where a `data` source returns different values across
plan invocations because the underlying AWS resource has changed or the query
returns results in a different order.

## Example
A `data "aws_ami"` source querying for the most recent Amazon Linux 2 AMI
returns a new AMI ID after AWS releases an updated AMI. If a resource depends
on this value (e.g., an EC2 launch template or ECS task definition), Terraform
will plan a replacement of that resource.

## Key Insight
This drift type is unique because *no human action* is required to introduce it.
Simply waiting for AWS to release a new AMI or update service defaults is sufficient.

## Detection Method
- Pin data source queries: use `filter` blocks with exact version constraints
- Use `most_recent = false` with explicit AMI IDs
- Run periodic `terraform plan` to detect when data source results change
