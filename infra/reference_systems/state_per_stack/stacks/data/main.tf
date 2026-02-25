terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws    = { source = "hashicorp/aws"; version = "~> 5.0" }
    random = { source = "hashicorp/random"; version = "~> 3.5" }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = "iac-maintainability-study"
      Variant     = "state-per-stack"
      Stack       = "data"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

locals { name_prefix = "${var.project_name}-${var.environment}" }

# Cross-stack references via data sources (SSM Parameter Store)
data "aws_ssm_parameter" "db_subnet_group_name" {
  name = "/${local.name_prefix}/network/db_subnet_group_name"
}

data "aws_ssm_parameter" "rds_sg_id" {
  name = "/${local.name_prefix}/security/rds_sg_id"
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
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

  db_subnet_group_name   = data.aws_ssm_parameter.db_subnet_group_name.value
  vpc_security_group_ids = [data.aws_ssm_parameter.rds_sg_id.value]

  backup_retention_period    = 7
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

# Publish to SSM for compute/observability stacks
resource "aws_ssm_parameter" "rds_address" {
  name  = "/${local.name_prefix}/data/rds_address"
  type  = "SecureString"
  value = aws_db_instance.this.address
}

resource "aws_ssm_parameter" "rds_port" {
  name  = "/${local.name_prefix}/data/rds_port"
  type  = "String"
  value = tostring(aws_db_instance.this.port)
}

resource "aws_ssm_parameter" "s3_bucket_name" {
  name  = "/${local.name_prefix}/data/s3_bucket_name"
  type  = "String"
  value = aws_s3_bucket.artifacts.bucket
}
