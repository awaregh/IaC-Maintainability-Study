terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name prefix"
  type        = string
  default     = "iac-study"
}

variable "tfstate_bucket" {
  description = "S3 bucket for remote state"
  type        = string
  default     = "iac-study-tfstate"
}

# This root module serves as documentation and CI orchestration helper.
# Each layer is deployed independently. Use the following commands in order:
#
# 1. cd layers/network  && terraform init && terraform apply
# 2. cd layers/security && terraform init && terraform apply
# 3. cd layers/data     && terraform init && terraform apply
# 4. cd layers/compute  && terraform init && terraform apply
# 5. cd layers/observability && terraform init && terraform apply
#
# Remote state configuration in each layer handles cross-layer data passing.

data "terraform_remote_state" "compute" {
  backend = "s3"
  config = {
    bucket = var.tfstate_bucket
    key    = "layer-based/compute/terraform.tfstate"
    region = var.aws_region
  }
}

data "terraform_remote_state" "data_layer" {
  backend = "s3"
  config = {
    bucket = var.tfstate_bucket
    key    = "layer-based/data/terraform.tfstate"
    region = var.aws_region
  }
}

output "alb_dns_name" {
  description = "Application Load Balancer DNS name"
  value       = data.terraform_remote_state.compute.outputs.alb_dns_name
}

output "s3_bucket_name" {
  description = "Artifacts S3 bucket name"
  value       = data.terraform_remote_state.data_layer.outputs.s3_bucket_name
}
