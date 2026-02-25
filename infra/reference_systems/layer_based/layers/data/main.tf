terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }

  backend "s3" {
    bucket         = "iac-study-tfstate"
    key            = "layer-based/data/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "iac-study-tfstate-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = "iac-maintainability-study"
      Variant     = "layer-based"
      Layer       = "data"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "project_name" {
  type    = string
  default = "iac-study"
}

variable "tfstate_bucket" {
  description = "S3 bucket containing remote state files"
  type        = string
  default     = "iac-study-tfstate"
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "db_name" {
  type    = string
  default = "appdb"
}

variable "db_username" {
  type    = string
  default = "dbadmin"
}

variable "db_password" {
  type      = string
  sensitive = true
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = var.tfstate_bucket
    key    = "layer-based/network/terraform.tfstate"
    region = var.aws_region
  }
}

data "terraform_remote_state" "security" {
  backend = "s3"
  config = {
    bucket = var.tfstate_bucket
    key    = "layer-based/security/terraform.tfstate"
    region = var.aws_region
  }
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_db_parameter_group" "this" {
  name   = "${local.name_prefix}-pg15"
  family = "postgres15"

  parameter {
    name  = "log_connections"
    value = "1"
  }

  tags = { Name = "${local.name_prefix}-pg-params" }
}

resource "aws_db_instance" "this" {
  identifier        = "${local.name_prefix}-postgres"
  engine            = "postgres"
  engine_version    = "15.4"
  instance_class    = var.db_instance_class
  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = data.terraform_remote_state.network.outputs.db_subnet_group_name
  vpc_security_group_ids = [data.terraform_remote_state.security.outputs.rds_sg_id]
  parameter_group_name   = aws_db_parameter_group.this.name

  backup_retention_period    = 7
  backup_window              = "03:00-04:00"
  maintenance_window         = "Mon:04:00-Mon:05:00"
  auto_minor_version_upgrade = true
  skip_final_snapshot        = var.environment != "prod"
  multi_az                   = var.environment == "prod"

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  tags = { Name = "${local.name_prefix}-postgres" }
}

resource "aws_s3_bucket" "artifacts" {
  bucket = "${local.name_prefix}-artifacts-${random_id.bucket_suffix.hex}"
  tags   = { Name = "${local.name_prefix}-artifacts" }
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "aws:kms" }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

output "rds_address" {
  value     = aws_db_instance.this.address
  sensitive = true
}

output "rds_port" {
  value = aws_db_instance.this.port
}

output "rds_identifier" {
  value = aws_db_instance.this.identifier
}

output "s3_bucket_name" {
  value = aws_s3_bucket.artifacts.bucket
}

output "s3_bucket_arn" {
  value = aws_s3_bucket.artifacts.arn
}
