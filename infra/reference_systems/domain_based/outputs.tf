output "vpc_id" {
  description = "VPC ID"
  value       = module.platform.vpc_id
}

output "alb_dns_name" {
  description = "Application Load Balancer DNS name"
  value       = module.app.alb_dns_name
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = module.app.ecs_cluster_name
}

output "rds_endpoint" {
  description = "RDS endpoint"
  value       = module.data.rds_address
  sensitive   = true
}

output "s3_bucket_name" {
  description = "S3 bucket name"
  value       = module.data.s3_bucket_name
}
