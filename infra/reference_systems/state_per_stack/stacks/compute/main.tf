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
      Stack       = "compute"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

locals { name_prefix = "${var.project_name}-${var.environment}" }

# Consume cross-stack data from SSM Parameter Store
data "aws_ssm_parameter" "private_subnet_ids" {
  name = "/${local.name_prefix}/network/private_subnet_ids"
}

data "aws_ssm_parameter" "public_subnet_ids" {
  name = "/${local.name_prefix}/network/public_subnet_ids"
}

data "aws_ssm_parameter" "vpc_id" {
  name = "/${local.name_prefix}/network/vpc_id"
}

data "aws_ssm_parameter" "alb_sg_id" {
  name = "/${local.name_prefix}/security/alb_sg_id"
}

data "aws_ssm_parameter" "ecs_tasks_sg_id" {
  name = "/${local.name_prefix}/security/ecs_tasks_sg_id"
}

data "aws_ssm_parameter" "task_execution_role_arn" {
  name = "/${local.name_prefix}/security/task_execution_role_arn"
}

data "aws_ssm_parameter" "task_role_arn" {
  name = "/${local.name_prefix}/security/task_role_arn"
}

data "aws_ssm_parameter" "rds_address" {
  name = "/${local.name_prefix}/data/rds_address"
}

data "aws_ssm_parameter" "rds_port" {
  name = "/${local.name_prefix}/data/rds_port"
}

data "aws_ssm_parameter" "s3_bucket_name" {
  name = "/${local.name_prefix}/data/s3_bucket_name"
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
  execution_role_arn       = data.aws_ssm_parameter.task_execution_role_arn.value
  task_role_arn            = data.aws_ssm_parameter.task_role_arn.value

  container_definitions = jsonencode([
    {
      name      = "app"
      image     = var.container_image
      essential = true
      portMappings = [{ containerPort = var.container_port, protocol = "tcp" }]
      environment = [
        { name = "DB_HOST", value = data.aws_ssm_parameter.rds_address.value },
        { name = "DB_PORT", value = data.aws_ssm_parameter.rds_port.value },
        { name = "DB_NAME", value = var.db_name },
        { name = "S3_BUCKET", value = data.aws_ssm_parameter.s3_bucket_name.value },
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
  security_groups    = [data.aws_ssm_parameter.alb_sg_id.value]
  subnets            = split(",", data.aws_ssm_parameter.public_subnet_ids.value)
  tags               = { Name = "${local.name_prefix}-alb" }
}

resource "aws_lb_target_group" "app" {
  name        = "${local.name_prefix}-app-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = data.aws_ssm_parameter.vpc_id.value
  target_type = "ip"

  health_check {
    enabled  = true
    path     = "/health"
    matcher  = "200"
    interval = 30
    timeout  = 5
  }
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
    subnets          = split(",", data.aws_ssm_parameter.private_subnet_ids.value)
    security_groups  = [data.aws_ssm_parameter.ecs_tasks_sg_id.value]
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
  tags       = { Name = "${local.name_prefix}-app-service" }
}
