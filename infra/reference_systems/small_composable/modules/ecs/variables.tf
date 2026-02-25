variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for ECS tasks"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for the ALB"
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "Security group ID for the ALB"
  type        = string
}

variable "ecs_tasks_security_group_id" {
  description = "Security group ID for ECS tasks"
  type        = string
}

variable "container_image" {
  description = "Docker image URI for the ECS task"
  type        = string
}

variable "container_port" {
  description = "Port the container listens on"
  type        = number
  default     = 80
}

variable "ecs_task_cpu" {
  description = "CPU units for ECS task"
  type        = number
  default     = 256
}

variable "ecs_task_memory" {
  description = "Memory in MiB for ECS task"
  type        = number
  default     = 512
}

variable "ecs_desired_count" {
  description = "Desired number of task replicas"
  type        = number
  default     = 2
}

variable "task_execution_role_arn" {
  description = "ARN of the ECS task execution IAM role"
  type        = string
}

variable "task_role_arn" {
  description = "ARN of the ECS task IAM role"
  type        = string
}

variable "environment_variables" {
  description = "Environment variables to inject into the container"
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "enable_deletion_protection" {
  description = "Enable ALB deletion protection"
  type        = bool
  default     = false
}
