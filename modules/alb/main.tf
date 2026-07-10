resource "aws_security_group" "alb" {
  name_prefix = "${var.name}-alb-"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-alb"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Only API Gateway's VPC Link (via ENIs in the VPC) needs to reach the ALB;
# restrict ingress to the VPC CIDR rather than the world since the ALB is private.
resource "aws_security_group_rule" "alb_ingress_http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  security_group_id = aws_security_group.alb.id
  cidr_blocks       = [var.vpc_cidr]
}

resource "aws_security_group_rule" "alb_to_nodeport" {
  type                     = "egress"
  from_port                = var.ingress_node_port
  to_port                  = var.ingress_node_port
  protocol                 = "tcp"
  security_group_id        = aws_security_group.alb.id
  source_security_group_id = var.node_security_group_id
}

resource "aws_security_group_rule" "node_from_alb" {
  type                     = "ingress"
  from_port                = var.ingress_node_port
  to_port                  = var.ingress_node_port
  protocol                 = "tcp"
  security_group_id        = var.node_security_group_id
  source_security_group_id = aws_security_group.alb.id
}

resource "aws_lb" "this" {
  name               = "${var.name}-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.private_subnet_ids

  tags = {
    Name = "${var.name}-alb"
  }
}

resource "aws_lb_target_group" "ingress" {
  name        = "${var.name}-ingress"
  port        = var.ingress_node_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    path                = "/healthz"
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = {
    Name = "${var.name}-ingress"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ingress.arn
  }
}

resource "aws_autoscaling_attachment" "worker" {
  autoscaling_group_name = var.worker_asg_name
  lb_target_group_arn    = aws_lb_target_group.ingress.arn
}
