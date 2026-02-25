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
    key            = "layer-based/compute/terraform.tfstate"
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
      Layer       = "compute"
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

variable "container_image" {
  type    = string
  default = "nginx:latest"
}

variable "container_port" {
  type    = number
  default = 80
}

variable "ecs_task_cpu" {
  type    = number
  default = 256
}

variable "ecs_task_memory" {
  type    = number
  default = 512
}

variable "ecs_desired_count" {
  type    = number
  default = 2
}

variable "db_name" {
  type    = string
  default = "appdb"
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

data "terraform_remote_state" "data_layer" {
  backend = "s3"
  config = {
    bucket = var.tfstate_bucket
    key    = "layer-based/data/terraform.tfstate"
    region = var.aws_region
  }
}

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${local.name_prefix}"
  retention_in_days = 30
  tags              = { Name = "${local.name_prefix}-ecs-logs" }
}

resource "aws_ecs_cluster" "this" {
  name = "${local.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = { Name = "${local.name_prefix}-cluster" }
}

resource "aws_ecs_task_definition" "app" {
  family                   = "${local.name_prefix}-app"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.ecs_task_cpu
  memory                   = var.ecs_task_memory
  execution_role_arn       = data.terraform_remote_state.security.outputs.task_execution_role_arn
  task_role_arn            = data.terraform_remote_state.security.outputs.task_role_arn

  container_definitions = jsonencode([
    {
      name      = "app"
      image     = var.container_image
      essential = true
      portMappings = [{ containerPort = var.container_port, protocol = "tcp" }]
      environment = [
        { name = "DB_HOST", value = data.terraform_remote_state.data_layer.outputs.rds_address },
        { name = "DB_PORT", value = tostring(data.terraform_remote_state.data_layer.outputs.rds_port) },
        { name = "DB_NAME", value = var.db_name },
        { name = "S3_BUCKET", value = data.terraform_remote_state.data_layer.outputs.s3_bucket_name },
        { name = "AWS_REGION", value = var.aws_region },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "app"
        }
      }
    }
  ])

  tags = { Name = "${local.name_prefix}-task-def" }
}

resource "aws_lb" "this" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [data.terraform_remote_state.security.outputs.alb_sg_id]
  subnets            = data.terraform_remote_state.network.outputs.public_subnet_ids

  tags = { Name = "${local.name_prefix}-alb" }
}

resource "aws_lb_target_group" "app" {
  name        = "${local.name_prefix}-app-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id
  target_type = "ip"

  health_check {
    enabled  = true
    path     = "/health"
    matcher  = "200"
    interval = 30
    timeout  = 5
  }

  tags = { Name = "${local.name_prefix}-app-tg" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_ecs_service" "app" {
  name            = "${local.name_prefix}-app"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.ecs_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.terraform_remote_state.network.outputs.private_subnet_ids
    security_groups  = [data.terraform_remote_state.security.outputs.ecs_tasks_sg_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "app"
    container_port   = var.container_port
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  depends_on = [aws_lb_listener.http]

  tags = { Name = "${local.name_prefix}-app-service" }
}

output "cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "service_name" {
  value = aws_ecs_service.app.name
}

output "alb_dns_name" {
  value = aws_lb.this.dns_name
}

output "alb_arn_suffix" {
  value = aws_lb.this.arn_suffix
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.ecs.name
}
