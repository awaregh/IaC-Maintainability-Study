# Drift Scenario 05: Partial Apply / State Issues

## Summary
Simulates an interrupted terraform apply that leaves infrastructure in a partially
provisioned state. This creates a divergence between the state file and reality.

## How It Happens
1. `terraform apply` starts creating/modifying resources
2. The process is interrupted (SIGTERM, network failure, timeout, EC2 spot interruption)
3. Some resources are created/modified, others are not
4. The state file partially reflects the intended end state
5. Subsequent `terraform plan` runs may show unexpected creates/destroys

## Real-World Impact
- VPC created, subnets not created → subsequent applies may try to recreate VPC
- ECS service updated, but task definition not updated → service runs old tasks
- RDS snapshot initiated but not completed → restore failure

## Detection Method
- `terraform plan` after re-running typically detects the incomplete state
- Compare `terraform state list` with actual AWS resource listing
- Check CloudTrail for failed resource creation events
