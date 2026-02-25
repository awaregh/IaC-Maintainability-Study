variable "aws_region" { type = string; default = "us-east-1" }
variable "environment" { type = string; default = "dev" }
variable "project_name" { type = string; default = "iac-study" }
variable "db_instance_class" { type = string; default = "db.t3.micro" }
variable "db_name" { type = string; default = "appdb" }
variable "db_username" { type = string; default = "dbadmin" }
variable "db_password" { type = string; sensitive = true }
