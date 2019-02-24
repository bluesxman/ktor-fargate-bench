terraform {
  backend "s3" {
    key    = "kfb/compute.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = "${var.region}"
}

locals {
  project = "kfb"
  vpc_id = "${data.terraform_remote_state.network.vpc_id}"
  public_subnets = "${data.terraform_remote_state.network.public_subnet_ids}"
  private_subnets = "${data.terraform_remote_state.network.private_subnet_ids}"
}

data "terraform_remote_state" "network" {
  backend = "s3"

  config {
    bucket = "com.smackwerks-tfstate"
    key    = "${local.project}/network.tfstate"
    region = "${var.region}"
  }
}

### Container registry
resource "aws_ecr_repository" "kfb" {
  name = "com.smackwerks.kfb.ecr"

  tags {
    Name = "${local.project}-ecr"
    Project = "${local.project}"
  }
}

### Security
resource "aws_security_group" "lb" {
  name        = "cb-load-balancer-security-group"
  description = "controls access to the ALB"
  vpc_id      = "${local.vpc_id}"

  ingress {
    protocol    = "tcp"
    from_port   = 3000
    to_port     = 3000
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name = "${local.project}-sg-load-balancer"
    Project = "${local.project}"
  }
}

resource "aws_security_group" "ecs_tasks" {
  name        = "cb-ecs-tasks-security-group"
  description = "allow inbound access from the ALB only"
  vpc_id      = "${local.vpc_id}"

  # Traffic to the ECS cluster should only come from the ALB
  ingress {
    protocol        = "tcp"
    from_port       = "${var.app_port}"
    to_port         = "${var.app_port}"
    security_groups = ["${aws_security_group.lb.id}"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name = "${local.project}-sg-ecs-tasks"
    Project = "${local.project}"
  }
}

### Load Balancer
resource "aws_alb" "main" {
  name            = "cb-load-balancer"
  subnets         = ["${local.public_subnets}"]  # beware of list bugs:  https://github.com/hashicorp/terraform/issues/13869
  security_groups = ["${aws_security_group.lb.id}"]
}

resource "aws_alb_target_group" "app" {
  name        = "cb-target-group"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = "${local.vpc_id}"
  target_type = "ip"

  health_check {
    healthy_threshold   = "3"
    interval            = "30"
    protocol            = "HTTP"
    matcher             = "200"
    timeout             = "3"
    path                = "/"
    unhealthy_threshold = "2"
  }
}

resource "aws_alb_listener" "front_end" {
  load_balancer_arn = "${aws_alb.main.id}"
  port              = "3000"
  protocol          = "HTTP"

  # Redirect all traffic from the ALB to the target group
  default_action {
    target_group_arn = "${aws_alb_target_group.app.id}"
    type             = "forward"
  }
}

### Outputs
output "ecr_url" {
  value = "${aws_ecr_repository.kfb.repository_url}"
}