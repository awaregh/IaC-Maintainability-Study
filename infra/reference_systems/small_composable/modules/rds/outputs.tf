output "endpoint" {
  description = "RDS instance connection endpoint"
  value       = aws_db_instance.this.endpoint
  sensitive   = true
}

output "address" {
  description = "RDS instance hostname"
  value       = aws_db_instance.this.address
  sensitive   = true
}

output "port" {
  description = "RDS instance port"
  value       = aws_db_instance.this.port
}

output "db_name" {
  description = "Name of the database"
  value       = aws_db_instance.this.db_name
}

output "identifier" {
  description = "RDS instance identifier"
  value       = aws_db_instance.this.identifier
}
