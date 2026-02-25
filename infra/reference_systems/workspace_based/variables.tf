variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name prefix"
  type        = string
  default     = "iac-study"
}

variable "container_image" {
  description = "Docker image URI"
  type        = string
  default     = "nginx:latest"
}

variable "alarm_email" {
  description = "Email for alarm notifications"
  type        = string
  default     = "ops@example.com"
}

variable "db_password" {
  description = "RDS master password"
  type        = string
  sensitive   = true
}
