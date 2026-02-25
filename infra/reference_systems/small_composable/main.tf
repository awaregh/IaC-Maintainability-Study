locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# Security groups are managed in the root to keep cross-module SG references clear
resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "ALB security group"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
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
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "Traffic from ALB"
    from_port       = var.container_port
    to_port         = var.container_port
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
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "PostgreSQL from ECS"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  tags = { Name = "${local.name_prefix}-rds-sg" }
}

module "vpc" {
  source             = "./modules/vpc"
  name_prefix        = local.name_prefix
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
}

module "s3" {
  source        = "./modules/s3"
  name_prefix   = local.name_prefix
  bucket_suffix = random_id.bucket_suffix.hex
}

module "iam" {
  source            = "./modules/iam"
  name_prefix       = local.name_prefix
  s3_bucket_arn     = module.s3.bucket_arn
  ecs_log_group_arn = module.ecs.log_group_name != "" ? "/aws/ecs/${local.name_prefix}" : "/aws/ecs/${local.name_prefix}"
}

module "ecs" {
  source                      = "./modules/ecs"
  name_prefix                 = local.name_prefix
  vpc_id                      = module.vpc.vpc_id
  private_subnet_ids          = module.vpc.private_subnet_ids
  public_subnet_ids           = module.vpc.public_subnet_ids
  alb_security_group_id       = aws_security_group.alb.id
  ecs_tasks_security_group_id = aws_security_group.ecs_tasks.id
  container_image             = var.container_image
  container_port              = var.container_port
  ecs_task_cpu                = var.ecs_task_cpu
  ecs_task_memory             = var.ecs_task_memory
  ecs_desired_count           = var.ecs_desired_count
  task_execution_role_arn     = module.iam.task_execution_role_arn
  task_role_arn               = module.iam.task_role_arn
  aws_region                  = var.aws_region
  enable_deletion_protection  = var.environment == "prod"

  environment_variables = [
    { name = "DB_HOST", value = module.rds.address },
    { name = "DB_PORT", value = tostring(module.rds.port) },
    { name = "DB_NAME", value = var.db_name },
    { name = "S3_BUCKET", value = module.s3.bucket_name },
    { name = "AWS_REGION", value = var.aws_region },
  ]
}

module "rds" {
  source                = "./modules/rds"
  name_prefix           = local.name_prefix
  vpc_id                = module.vpc.vpc_id
  db_subnet_group_name  = module.vpc.db_subnet_group_name
  rds_security_group_id = aws_security_group.rds.id
  db_instance_class     = var.db_instance_class
  db_name               = var.db_name
  db_username           = var.db_username
  db_password           = var.db_password
  multi_az              = var.environment == "prod"
  deletion_protection   = var.environment == "prod"
  skip_final_snapshot   = var.environment != "prod"
}

module "monitoring" {
  source           = "./modules/monitoring"
  name_prefix      = local.name_prefix
  alarm_email      = var.alarm_email
  ecs_cluster_name = module.ecs.cluster_name
  ecs_service_name = module.ecs.service_name
  rds_identifier   = module.rds.identifier
  alb_arn_suffix   = module.ecs.alb_arn_suffix
  aws_region       = var.aws_region
}
