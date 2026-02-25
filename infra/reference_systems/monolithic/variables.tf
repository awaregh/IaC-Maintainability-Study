variable "aws_region" {
  description = "AWS region to deploy resources into"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name used as a prefix for all resource names"
  type        = string
  default     = "iac-study"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones to use for subnets"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "container_image" {
  description = "Docker image URI for the ECS service"
  type        = string
  default     = "nginx:latest"
}

variable "container_port" {
  description = "Port the container listens on"
  type        = number
  default     = 80
}

variable "ecs_task_cpu" {
  description = "CPU units for ECS task (1 vCPU = 1024)"
  type        = number
  default     = 256
}

variable "ecs_task_memory" {
  description = "Memory in MiB for ECS task"
  type        = number
  default     = 512
}

variable "ecs_desired_count" {
  description = "Desired number of ECS task replicas"
  type        = number
  default     = 2
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "Name of the PostgreSQL database"
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Master username for RDS"
  type        = string
  default     = "dbadmin"
}

variable "db_password" {
  description = "Master password for RDS (use Secrets Manager in production)"
  type        = string
  sensitive   = true
}

variable "s3_bucket_name" {
  description = "Globally unique S3 bucket name suffix"
  type        = string
  default     = "artifacts"
}

variable "alarm_email" {
  description = "Email address for CloudWatch alarm notifications"
  type        = string
  default     = "ops@example.com"
}
