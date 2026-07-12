data "aws_availability_zones" "available" {
  state = "available"
}

# --- VPC: public / private-with-egress / isolated tiers, mirroring the source CDK stack.
# nat_gateways=0 there means the "private" tier has no default route either; only the
# isolated tier (where RDS actually lives) is meaningfully different from private here.
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = var.name
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name}-igw"
  }
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.name}-public-${count.index}"
  }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.name}-private-${count.index}"
  }
}

resource "aws_subnet" "isolated" {
  count             = length(var.isolated_subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.isolated_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.name}-isolated-${count.index}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# private and isolated subnets keep the VPC's default (local-only) route table —
# no NAT gateway is created here, matching the source stack's nat_gateways=0.

# --- security group: PostgreSQL from within the VPC only, no default egress ---
resource "aws_security_group" "db" {
  name_prefix = "${var.name}-db-"
  description = "Security group for RDS PostgreSQL instance"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "Allow PostgreSQL from within VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.this.cidr_block]
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
  subnet_ids  = aws_subnet.isolated[*].id

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
