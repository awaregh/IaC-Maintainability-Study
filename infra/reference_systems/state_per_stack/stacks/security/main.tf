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
      Stack       = "security"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

locals { name_prefix = "${var.project_name}-${var.environment}" }

data "aws_ssm_parameter" "vpc_id" {
  name = "/${local.name_prefix}/network/vpc_id"
}

data "aws_iam_policy_document" "ecs_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task_execution" {
  name               = "${local.name_prefix}-ecs-task-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
  tags               = { Name = "${local.name_prefix}-ecs-task-execution" }
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "task" {
  name               = "${local.name_prefix}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
  tags               = { Name = "${local.name_prefix}-ecs-task" }
}

resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "ALB security group"
  vpc_id      = data.aws_ssm_parameter.vpc_id.value

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-alb-sg" }
}

resource "aws_security_group" "ecs_tasks" {
  name        = "${local.name_prefix}-ecs-tasks-sg"
  description = "ECS tasks security group"
  vpc_id      = data.aws_ssm_parameter.vpc_id.value

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-ecs-tasks-sg" }
}

resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg"
  description = "RDS security group"
  vpc_id      = data.aws_ssm_parameter.vpc_id.value

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  tags = { Name = "${local.name_prefix}-rds-sg" }
}

# Publish outputs to SSM Parameter Store for cross-stack consumption
resource "aws_ssm_parameter" "task_execution_role_arn" {
  name  = "/${local.name_prefix}/security/task_execution_role_arn"
  type  = "String"
  value = aws_iam_role.task_execution.arn
}

resource "aws_ssm_parameter" "task_role_arn" {
  name  = "/${local.name_prefix}/security/task_role_arn"
  type  = "String"
  value = aws_iam_role.task.arn
}
