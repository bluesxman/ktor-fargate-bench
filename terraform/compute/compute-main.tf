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
}

### Outputs
output "ecr_url" {
  value = "${aws_ecr_repository.kfb.repository_url}"
}