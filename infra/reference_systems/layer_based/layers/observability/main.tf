terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "iac-study-tfstate"
    key            = "layer-based/observability/terraform.tfstate"
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
      Layer       = "observability"
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

variable "alarm_email" {
  description = "Email for CloudWatch alarm notifications"
  type        = string
  default     = "ops@example.com"
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

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

resource "aws_sns_topic" "alarms" {
  name = "${local.name_prefix}-alarms"
  tags = { Name = "${local.name_prefix}-alarms" }
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

resource "aws_cloudwatch_metric_alarm" "ecs_cpu_high" {
  alarm_name          = "${local.name_prefix}-ecs-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_actions       = [aws_sns_topic.alarms.arn]

  dimensions = {
    ClusterName = data.terraform_remote_state.compute.outputs.cluster_name
    ServiceName = data.terraform_remote_state.compute.outputs.service_name
  }
}

resource "aws_cloudwatch_metric_alarm" "ecs_memory_high" {
  alarm_name          = "${local.name_prefix}-ecs-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_actions       = [aws_sns_topic.alarms.arn]

  dimensions = {
    ClusterName = data.terraform_remote_state.compute.outputs.cluster_name
    ServiceName = data.terraform_remote_state.compute.outputs.service_name
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_cpu_high" {
  alarm_name          = "${local.name_prefix}-rds-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 75
  alarm_actions       = [aws_sns_topic.alarms.arn]

  dimensions = {
    DBInstanceIdentifier = data.terraform_remote_state.data_layer.outputs.rds_identifier
  }
}

resource "aws_cloudwatch_metric_alarm" "alb_5xx_errors" {
  alarm_name          = "${local.name_prefix}-alb-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  alarm_actions       = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = data.terraform_remote_state.compute.outputs.alb_arn_suffix
  }
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${local.name_prefix}-overview"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "ECS Utilization"
          period = 300
          stat   = "Average"
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", data.terraform_remote_state.compute.outputs.cluster_name, "ServiceName", data.terraform_remote_state.compute.outputs.service_name],
            ["AWS/ECS", "MemoryUtilization", "ClusterName", data.terraform_remote_state.compute.outputs.cluster_name, "ServiceName", data.terraform_remote_state.compute.outputs.service_name],
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "RDS CPU"
          period = 300
          stat   = "Average"
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", data.terraform_remote_state.data_layer.outputs.rds_identifier],
          ]
        }
      }
    ]
  })
}

output "sns_alarms_arn" {
  value = aws_sns_topic.alarms.arn
}

output "dashboard_name" {
  value = aws_cloudwatch_dashboard.main.dashboard_name
}
