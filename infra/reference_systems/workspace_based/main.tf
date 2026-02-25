locals {
  # Environment-specific configuration driven by Terraform workspace
  workspace = terraform.workspace

  env_config = {
    dev = {
      vpc_cidr          = "10.0.0.0/16"
      db_instance_class = "db.t3.micro"
      ecs_desired_count = 1
      ecs_task_cpu      = 256
      ecs_task_memory   = 512
      multi_az          = false
      deletion_protection = false
      container_port    = 80
    }
    staging = {
      vpc_cidr          = "10.1.0.0/16"
      db_instance_class = "db.t3.small"
      ecs_desired_count = 2
      ecs_task_cpu      = 512
      ecs_task_memory   = 1024
      multi_az          = false
      deletion_protection = false
      container_port    = 80
    }
    prod = {
      vpc_cidr          = "10.2.0.0/16"
      db_instance_class = "db.t3.medium"
      ecs_desired_count = 3
      ecs_task_cpu      = 1024
      ecs_task_memory   = 2048
      multi_az          = true
      deletion_protection = true
      container_port    = 80
    }
  }

  config      = local.env_config[local.workspace]
  name_prefix = "${var.project_name}-${local.workspace}"

  azs = ["${var.aws_region}a", "${var.aws_region}b", "${var.aws_region}c"]

  public_cidr_blocks = [
    cidrsubnet(local.config.vpc_cidr, 8, 0),
    cidrsubnet(local.config.vpc_cidr, 8, 1),
    cidrsubnet(local.config.vpc_cidr, 8, 2),
  ]
  private_cidr_blocks = [
    cidrsubnet(local.config.vpc_cidr, 8, 10),
    cidrsubnet(local.config.vpc_cidr, 8, 11),
    cidrsubnet(local.config.vpc_cidr, 8, 12),
  ]
  db_cidr_blocks = [
    cidrsubnet(local.config.vpc_cidr, 8, 20),
    cidrsubnet(local.config.vpc_cidr, 8, 21),
    cidrsubnet(local.config.vpc_cidr, 8, 22),
  ]
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# ── VPC ──────────────────────────────────────────────────────────────────────

resource "aws_vpc" "main" {
  cidr_block           = local.config.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = "${local.name_prefix}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name_prefix}-igw" }
}

resource "aws_subnet" "public" {
  count                   = 3
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_cidr_blocks[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true
  tags                    = { Name = "${local.name_prefix}-public-${count.index + 1}" }
}

resource "aws_subnet" "private" {
  count             = 3
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.private_cidr_blocks[count.index]
  availability_zone = local.azs[count.index]
  tags              = { Name = "${local.name_prefix}-private-${count.index + 1}" }
}

resource "aws_subnet" "database" {
  count             = 3
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.db_cidr_blocks[count.index]
  availability_zone = local.azs[count.index]
  tags              = { Name = "${local.name_prefix}-db-${count.index + 1}" }
}

resource "aws_eip" "nat" {
  count  = 3
  domain = "vpc"
  tags   = { Name = "${local.name_prefix}-nat-eip-${count.index + 1}" }
}

resource "aws_nat_gateway" "main" {
  count         = 3
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  depends_on    = [aws_internet_gateway.main]
  tags          = { Name = "${local.name_prefix}-nat-${count.index + 1}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "${local.name_prefix}-public-rt" }
}

resource "aws_route_table" "private" {
  count  = 3
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }
  tags = { Name = "${local.name_prefix}-private-rt-${count.index + 1}" }
}

resource "aws_route_table_association" "public" {
  count          = 3
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = 3
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

resource "aws_db_subnet_group" "main" {
  name       = "${local.name_prefix}-db-subnet-group"
  subnet_ids = aws_subnet.database[*].id
  tags       = { Name = "${local.name_prefix}-db-subnet-group" }
}

# ── Security Groups ───────────────────────────────────────────────────────────

resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "ALB security group"
  vpc_id      = aws_vpc.main.id

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
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = local.config.container_port
    to_port         = local.config.container_port
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
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  tags = { Name = "${local.name_prefix}-rds-sg" }
}

# ── IAM ───────────────────────────────────────────────────────────────────────

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

data "aws_iam_policy_document" "task_permissions" {
  statement {
    sid    = "S3Access"
    effect = "Allow"
    actions = [
      "s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket",
    ]
    resources = [aws_s3_bucket.artifacts.arn, "${aws_s3_bucket.artifacts.arn}/*"]
  }
}

resource "aws_iam_role_policy" "task_permissions" {
  name   = "${local.name_prefix}-task-permissions"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task_permissions.json
}

# ── S3 ────────────────────────────────────────────────────────────────────────

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

# ── RDS ───────────────────────────────────────────────────────────────────────

resource "aws_db_instance" "postgres" {
  identifier        = "${local.name_prefix}-postgres"
  engine            = "postgres"
  engine_version    = "15.4"
  instance_class    = local.config.db_instance_class
  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = "appdb"
  username = "dbadmin"
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  backup_retention_period    = 7
  backup_window              = "03:00-04:00"
  maintenance_window         = "Mon:04:00-Mon:05:00"
  auto_minor_version_upgrade = true
  deletion_protection        = local.config.deletion_protection
  skip_final_snapshot        = !local.config.deletion_protection
  multi_az                   = local.config.multi_az

  tags = { Name = "${local.name_prefix}-postgres" }
}

# ── ECS ───────────────────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${local.name_prefix}"
  retention_in_days = 30
  tags              = { Name = "${local.name_prefix}-ecs-logs" }
}

resource "aws_ecs_cluster" "main" {
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
  cpu                      = local.config.ecs_task_cpu
  memory                   = local.config.ecs_task_memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name      = "app"
      image     = var.container_image
      essential = true
      portMappings = [{ containerPort = local.config.container_port, protocol = "tcp" }]
      environment = [
        { name = "DB_HOST", value = aws_db_instance.postgres.address },
        { name = "DB_PORT", value = tostring(aws_db_instance.postgres.port) },
        { name = "DB_NAME", value = "appdb" },
        { name = "S3_BUCKET", value = aws_s3_bucket.artifacts.bucket },
        { name = "ENV", value = local.workspace },
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

resource "aws_lb" "main" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  enable_deletion_protection = local.config.deletion_protection
  tags                       = { Name = "${local.name_prefix}-alb" }
}

resource "aws_lb_target_group" "app" {
  name        = "${local.name_prefix}-app-tg"
  port        = local.config.container_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
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
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_ecs_service" "app" {
  name            = "${local.name_prefix}-app"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = local.config.ecs_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "app"
    container_port   = local.config.container_port
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  depends_on = [aws_lb_listener.http, aws_iam_role_policy_attachment.task_execution]
  tags       = { Name = "${local.name_prefix}-app-service" }
}

# ── CloudWatch ────────────────────────────────────────────────────────────────

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
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.app.name
  }
}
