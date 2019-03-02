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
  task_count = "${length(local.public_subnets)}"
  app_image = "${aws_ecr_repository.kfb.repository_url}:latest"
  task_cpu = 2048
  task_memory = 4096
  app_port = 8080
  service_name = "${local.project}-service"

  task_def = <<DEF
[
  {
    "name": "${local.project}-app",
    "image": "${local.app_image}",
    "cpu": ${local.task_cpu},
    "memory": ${local.task_memory},
    "networkMode": "awsvpc",
    "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/${local.project}-app",
          "awslogs-region": "${var.region}",
          "awslogs-stream-prefix": "ecs"
        }
    },
    "portMappings": [
      {
        "containerPort": ${local.app_port},
        "hostPort": ${local.app_port}
      }
    ]
  }
]
  DEF
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
  name = "com.smackwerks.kfb"

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
  name            = "${local.project}load-balancer"
  subnets         = ["${local.public_subnets}"]  # beware of list bugs:  https://github.com/hashicorp/terraform/issues/13869
  security_groups = ["${aws_security_group.lb.id}"]
}

resource "aws_alb_target_group" "app" {
  name        = "${local.project}-target-group"
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

### Policies and Roles
# read from ECR
# write logs
data "aws_iam_policy_document" "task_execution" {
 statement {
   actions = [
    "ecr:GetAuthorizationToken",
    "ecr:BatchCheckLayerAvailability",
    "ecr:GetDownloadUrlForLayer",
    "ecr:BatchGetImage"
   ]

   resources = ["${aws_ecr_repository.kfb.arn}"]
 }

 statement {
   actions = [
    "logs:CreateLogStream",
    "logs:PutLogEvents"
   ]

   resources = ["*"]
 }
}

data "aws_iam_policy_document" "ecs_assume_role" {
  statement {
    principals {
      type = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
    actions = [
      "sts:AssumeRole"
    ]
  }
}

# role allowing assume role by ECS
resource "aws_iam_policy" "task_execution" {
  policy = "${data.aws_iam_policy_document.task_execution.json}"
}

resource "aws_iam_role" "task_execution" {
  name = "${local.project}-task-execution-role"
  assume_role_policy = "${data.aws_iam_policy_document.ecs_assume_role.json}"
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  policy_arn = "${aws_iam_policy.task_execution.arn}"
  role = "${aws_iam_role.task_execution.name}"
}

# role allowing ECS service to CRUD service-linked roles
data "aws_iam_policy_document" "ecs_service_linked_role" {
  statement {
    actions = [
      "iam:CreateServiceLinkedRole",
      "iam:PutRolePolicy",
      "iam:UpdateRoleDescription",
      "iam:DeleteServiceLinkedRole",
      "iam:GetServiceLinkedRoleDeletionStatus"
    ]
    resources = ["arn:aws:iam::*:role/aws-service-role/ecs.amazonaws.com/AWSServiceRoleForECS*"]
    condition {
      test = "StringLike"
      values = ["ecs.amazonaws.com"]
      variable = "iam:AWSServiceName"
    }
  }
}

resource "aws_iam_policy" "ecs_service_linking" {
  policy = "${data.aws_iam_policy_document.ecs_service_linked_role.json}"
}

resource "aws_iam_service_linked_role" "kfb" {
  aws_service_name = "ecs.amazonaws.com"
}


### Compute Cluster
resource "aws_ecs_cluster" "main" {
  name = "${local.project}-cluster"
}

resource "aws_ecs_task_definition" "app" {
  family                   = "${local.project}-app-task"
  execution_role_arn       = "${aws_iam_role.task_execution.arn}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "${local.task_cpu}"
  memory                   = "${local.task_memory}"
  container_definitions    = "${local.task_def}"
}

resource "aws_ecs_service" "main" {
  name            = "${local.service_name}"
  cluster         = "${aws_ecs_cluster.main.id}"
  task_definition = "${aws_ecs_task_definition.app.arn}"
  desired_count   = "${local.task_count}"
  launch_type     = "FARGATE"

  network_configuration {
    security_groups  = ["${aws_security_group.ecs_tasks.id}"]
    subnets          = ["${local.private_subnets}"]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = "${aws_alb_target_group.app.id}"
    container_name   = "${local.project}-app"
    container_port   = "${var.app_port}"
  }

  depends_on = [
    "aws_alb_listener.front_end",
  ]
}

### Outputs
output "ecr_url" {
  value = "${aws_ecr_repository.kfb.repository_url}"
}