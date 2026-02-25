variable "name_prefix" {
  description = "Prefix for monitoring resource names"
  type        = string
}

variable "alarm_email" {
  description = "Email address to receive CloudWatch alarm notifications"
  type        = string
}

variable "ecs_cluster_name" {
  description = "Name of the ECS cluster to monitor"
  type        = string
}

variable "ecs_service_name" {
  description = "Name of the ECS service to monitor"
  type        = string
}

variable "rds_identifier" {
  description = "Identifier of the RDS instance to monitor"
  type        = string
}

variable "alb_arn_suffix" {
  description = "ARN suffix of the ALB to monitor"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}
