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
    key            = "workspace-based/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "iac-study-tfstate-lock"
    encrypt        = true
    # Workspace state paths: workspace-based/env:/dev/terraform.tfstate
    workspace_key_prefix = "workspace-based/env:"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "iac-maintainability-study"
      Variant     = "workspace-based"
      Environment = terraform.workspace
      ManagedBy   = "terraform"
    }
  }
}
