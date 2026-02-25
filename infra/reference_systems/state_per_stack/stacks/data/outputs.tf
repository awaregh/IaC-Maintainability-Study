output "rds_identifier" {
  description = "RDS instance identifier"
  value       = aws_db_instance.this.identifier
}

output "s3_bucket_name" {
  description = "S3 bucket name"
  value       = aws_s3_bucket.artifacts.bucket
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.artifacts.arn
}
