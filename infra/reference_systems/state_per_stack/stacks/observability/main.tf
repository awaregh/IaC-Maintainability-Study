terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = { source = "hashicorp/aws"; version = "~> 5.0" }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project     = "iac-maintainability-study"
      Variant     = "state-per-stack"
      Stack       = "observability"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

locals { name_prefix = "${var.project_name}-${var.environment}" }

data "aws_ssm_parameter" "cluster_name" {
  name = "/${local.name_prefix}/compute/cluster_name"
}

data "aws_ssm_parameter" "service_name" {
  name = "/${local.name_prefix}/compute/service_name"
}

data "aws_ssm_parameter" "rds_identifier" {
  name = "/${local.name_prefix}/data/rds_identifier"
}

data "aws_ssm_parameter" "alb_arn_suffix" {
  name = "/${local.name_prefix}/compute/alb_arn_suffix"
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
    ClusterName = data.aws_ssm_parameter.cluster_name.value
    ServiceName = data.aws_ssm_parameter.service_name.value
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
    DBInstanceIdentifier = data.aws_ssm_parameter.rds_identifier.value
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
    LoadBalancer = data.aws_ssm_parameter.alb_arn_suffix.value
  }
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${local.name_prefix}-overview"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0; y = 0; width = 12; height = 6
        properties = {
          title  = "ECS Utilization"
          period = 300
          stat   = "Average"
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", data.aws_ssm_parameter.cluster_name.value, "ServiceName", data.aws_ssm_parameter.service_name.value],
            ["AWS/ECS", "MemoryUtilization", "ClusterName", data.aws_ssm_parameter.cluster_name.value, "ServiceName", data.aws_ssm_parameter.service_name.value],
          ]
        }
      }
    ]
  })
}
