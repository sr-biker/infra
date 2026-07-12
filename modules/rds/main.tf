# --- security group: PostgreSQL from the k8s worker/control-plane node SG only ---
resource "aws_security_group" "db" {
  name_prefix = "${var.name}-db-"
  description = "Security group for RDS PostgreSQL instance"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Allow PostgreSQL from k8s nodes"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.node_security_group_id]
  }

  tags = {
    Name = "${var.name}-db"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_subnet_group" "this" {
  name        = "${var.name}-db-subnet-group"
  description = "Subnet group for RDS instance"
  subnet_ids  = var.private_subnet_ids

  tags = {
    Name = "${var.name}-db-subnet-group"
  }
}

# --- enhanced monitoring role, required by monitoring_interval > 0 ---
resource "aws_iam_role" "monitoring" {
  name = "${var.name}-rds-monitoring"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "monitoring" {
  role       = aws_iam_role.monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# --- master credentials: an existing Secrets Manager secret, not an RDS-managed one ---
# Reuses the same credentials as the source CDK stack's (now-decommissioned) instance,
# migrated from a us-east-2 secret of the same name -- not a fresh manage_master_user_password
# generated secret.
data "aws_secretsmanager_secret" "master" {
  name = var.master_secret_name
}

data "aws_secretsmanager_secret_version" "master" {
  secret_id = data.aws_secretsmanager_secret.master.id
}

locals {
  master_credentials = jsondecode(data.aws_secretsmanager_secret_version.master.secret_string)
}

# --- RDS PostgreSQL instance ---
resource "aws_db_instance" "postgres" {
  identifier     = "${var.name}-postgres"
  engine         = "postgres"
  engine_version = var.engine_version

  instance_class = var.instance_class

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]

  db_name  = var.database_name
  username = local.master_credentials.username
  password = local.master_credentials.password

  multi_az              = false
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_encrypted     = true
  publicly_accessible   = false
  deletion_protection   = false
  skip_final_snapshot   = true

  performance_insights_enabled = false
  monitoring_interval          = var.monitoring_interval
  monitoring_role_arn          = aws_iam_role.monitoring.arn

  tags = {
    Name = "${var.name}-postgres"
  }
}

# --- scheduled stop/start via EventBridge Scheduler ---
resource "aws_iam_role" "scheduler" {
  name = "${var.name}-rds-scheduler"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "scheduler" {
  name = "${var.name}-stop-start-rds"
  role = aws_iam_role.scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["rds:StopDBInstance", "rds:StartDBInstance"]
      Resource = aws_db_instance.postgres.arn
    }]
  })
}

resource "aws_scheduler_schedule" "stop_rds" {
  name                         = "${var.name}-stop-rds"
  schedule_expression          = var.stop_schedule_expression
  schedule_expression_timezone = "UTC"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:rds:stopDBInstance"
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({ DbInstanceIdentifier = aws_db_instance.postgres.identifier })
  }
}

resource "aws_scheduler_schedule" "start_rds" {
  name                         = "${var.name}-start-rds"
  schedule_expression          = var.start_schedule_expression
  schedule_expression_timezone = "UTC"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:rds:startDBInstance"
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({ DbInstanceIdentifier = aws_db_instance.postgres.identifier })
  }
}
