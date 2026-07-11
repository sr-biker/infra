data "aws_region" "current" {}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    # arm64 to match the Graviton (t4g) instance types below.
    name   = "name"
    values = ["al2023-ami-2023.*-kernel-*-arm64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }
}

locals {
  join_param_name = "/${var.name}/kubeadm-join-command"
}

# --- IAM: nodes need SSM (join command exchange) + SSM Session Manager for access ---
resource "aws_iam_role" "node" {
  name = "${var.name}-k8s-node"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "join_param" {
  name = "${var.name}-join-param"
  role = aws_iam_role.node.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:PutParameter", "ssm:GetParameter"]
      Resource = "arn:aws:ssm:${data.aws_region.current.region}:*:parameter${local.join_param_name}"
    }]
  })
}

resource "aws_iam_role_policy" "cloudwatch_logs" {
  name = "${var.name}-cloudwatch-logs"
  role = aws_iam_role.node.id

  # No IRSA/pod identity here (kubeadm, not EKS) — this is the instance profile every pod
  # on every node implicitly gets, so it's scoped to this cluster's log-group prefix only,
  # not "logs:*" on everything. Used by the aws-for-fluent-bit DaemonSet
  # (live/prod/cloudwatch-log-shipper.yaml) to ship container logs to CloudWatch Logs.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
        "logs:PutRetentionPolicy",
      ]
      Resource = "arn:aws:logs:${data.aws_region.current.region}:*:log-group:/${var.name}/*"
    }]
  })
}

resource "aws_iam_instance_profile" "node" {
  name = "${var.name}-k8s-node"
  role = aws_iam_role.node.name
}

# --- security group: cluster-internal traffic + SG-referenced ALB access ---
resource "aws_security_group" "node" {
  name_prefix = "${var.name}-node-"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-node"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "node_to_node" {
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.node.id
  self              = true
}

resource "aws_security_group_rule" "vpc_https" {
  type              = "ingress"
  from_port         = 6443
  to_port           = 6443
  protocol          = "tcp"
  security_group_id = aws_security_group.node.id
  cidr_blocks       = [var.vpc_cidr]
}

# --- control plane (single instance) ---
resource "aws_instance" "control_plane" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.control_plane_instance_type
  subnet_id              = var.private_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.node.id]
  iam_instance_profile   = aws_iam_instance_profile.node.name

  user_data = templatefile("${path.module}/templates/control-plane.sh.tpl", {
    kubernetes_version = var.kubernetes_version
    join_param_name    = local.join_param_name
  })

  tags = {
    Name = "${var.name}-control-plane"
    Role = "control-plane"
  }
}

# --- workers (autoscaling group across private subnets) ---
resource "aws_launch_template" "worker" {
  name_prefix   = "${var.name}-worker-"
  image_id      = data.aws_ami.al2023.id
  instance_type = var.worker_instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.node.name
  }

  vpc_security_group_ids = [aws_security_group.node.id]

  user_data = base64encode(templatefile("${path.module}/templates/worker.sh.tpl", {
    kubernetes_version = var.kubernetes_version
    join_param_name    = local.join_param_name
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.name}-worker"
      Role = "worker"
    }
  }

  depends_on = [aws_instance.control_plane]
}

resource "aws_autoscaling_group" "worker" {
  name                = "${var.name}-worker"
  desired_capacity    = var.worker_count
  min_size            = var.worker_count
  max_size            = var.worker_count
  vpc_zone_identifier = var.private_subnet_ids

  launch_template {
    id      = aws_launch_template.worker.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.name}-worker"
    propagate_at_launch = true
  }
}
