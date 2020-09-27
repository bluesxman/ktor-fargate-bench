### Security groups for the load balancer and ecs cluster

resource "aws_security_group" "lb" {
  name        = "${local.project}-load-balancer-security-group"
  description = "controls access to the ALB"
  vpc_id      = local.vpc_id

  ingress {
    protocol    = "tcp"
    from_port   = local.elb_port
    to_port     = local.elb_port
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${local.project}-sg-load-balancer"
    Project = local.project
  }
}

resource "aws_security_group" "ecs_tasks" {
  name        = "${local.project}-sg-ecs-tasks"
  description = "allow inbound access from the ALB only"
  vpc_id      = local.vpc_id

  # Traffic to the ECS cluster should only come from the ALB
  ingress {
    protocol        = "tcp"
    from_port       = local.elb_port
    to_port         = local.app_port
    security_groups = [aws_security_group.lb.id]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${local.project}-sg-ecs-tasks"
    Project = local.project
  }
}

