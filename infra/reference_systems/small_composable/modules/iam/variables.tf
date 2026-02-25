variable "name_prefix" {
  description = "Prefix for IAM resource names"
  type        = string
}

variable "s3_bucket_arn" {
  description = "ARN of the S3 bucket the ECS task can access"
  type        = string
}

variable "ecs_log_group_arn" {
  description = "ARN of the ECS CloudWatch log group"
  type        = string
}
