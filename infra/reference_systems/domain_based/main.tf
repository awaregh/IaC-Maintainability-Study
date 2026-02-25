locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

module "platform" {
  source             = "./modules/platform"
  name_prefix        = local.name_prefix
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  alarm_email        = var.alarm_email
  aws_region         = var.aws_region
}

module "data" {
  source                      = "./modules/data"
  name_prefix                 = local.name_prefix
  vpc_id                      = module.platform.vpc_id
  db_subnet_group_name        = module.platform.db_subnet_group_name
  ecs_tasks_security_group_id = module.app.ecs_tasks_security_group_id
  db_instance_class           = var.db_instance_class
  db_name                     = var.db_name
  db_username                 = var.db_username
  db_password                 = var.db_password
  bucket_suffix               = random_id.bucket_suffix.hex
  multi_az                    = var.environment == "prod"
  deletion_protection         = var.environment == "prod"
}

module "app" {
  source                     = "./modules/app"
  name_prefix                = local.name_prefix
  vpc_id                     = module.platform.vpc_id
  private_subnet_ids         = module.platform.private_subnet_ids
  public_subnet_ids          = module.platform.public_subnet_ids
  container_image            = var.container_image
  container_port             = var.container_port
  ecs_task_cpu               = var.ecs_task_cpu
  ecs_task_memory            = var.ecs_task_memory
  ecs_desired_count          = var.ecs_desired_count
  db_host                    = module.data.rds_address
  db_port                    = module.data.rds_port
  db_name                    = var.db_name
  s3_bucket_name             = module.data.s3_bucket_name
  s3_bucket_arn              = module.data.s3_bucket_arn
  aws_region                 = var.aws_region
  enable_deletion_protection = var.environment == "prod"
  sns_alarms_arn             = module.platform.sns_alarms_arn
}
