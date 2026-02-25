output "task_execution_role_arn" {
  description = "ECS task execution role ARN"
  value       = aws_iam_role.task_execution.arn
}

output "task_role_arn" {
  description = "ECS task role ARN"
  value       = aws_iam_role.task.arn
}

output "task_role_id" {
  description = "ECS task role ID"
  value       = aws_iam_role.task.id
}

output "alb_sg_id" {
  description = "ALB security group ID"
  value       = aws_security_group.alb.id
}

output "ecs_tasks_sg_id" {
  description = "ECS tasks security group ID"
  value       = aws_security_group.ecs_tasks.id
}

output "rds_sg_id" {
  description = "RDS security group ID"
  value       = aws_security_group.rds.id
}
