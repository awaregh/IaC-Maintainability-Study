output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.this.name
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.app.name
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = aws_lb.this.dns_name
}

output "alb_arn_suffix" {
  description = "ALB ARN suffix"
  value       = aws_lb.this.arn_suffix
}

output "ecs_tasks_security_group_id" {
  description = "Security group ID for ECS tasks (used by data module for RDS access)"
  value       = aws_security_group.ecs_tasks.id
}
