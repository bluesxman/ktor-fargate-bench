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
  elb_port = 80
  service_name = "${local.project}-service"

  # TODO: Test removing hostPort in the port mappings
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
  name        = "${local.project}-load-balancer-security-group"
  description = "controls access to the ALB"
  vpc_id      = "${local.vpc_id}"

  ingress {
    protocol    = "tcp"
    from_port   = "${local.elb_port}"
    to_port     = "${local.elb_port}"
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
  name        = "${local.project}-ecs-tasks-security-group"
  description = "allow inbound access from the ALB only"
  vpc_id      = "${local.vpc_id}"

  # Traffic to the ECS cluster should only come from the ALB
  ingress {
    protocol        = "tcp"
    from_port       = "${local.elb_port}"
    to_port         = "${local.app_port}"
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
  name            = "${local.project}-load-balancer"
  subnets         = ["${local.public_subnets}"]  # beware of list bugs:  https://github.com/hashicorp/terraform/issues/13869
  security_groups = ["${aws_security_group.lb.id}"]
}

resource "aws_alb_target_group" "app" {
  name        = "${local.project}-target-group"
  port        = "${local.app_port}"
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
  port              = "${local.elb_port}"
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

//   resources = ["${aws_ecr_repository.kfb.arn}"]
   resources = ["*"]
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


# Setup the task role.  Read on s3
# TODO: read remote state of data stack to get the bucket name
data "aws_iam_policy_document" "task_s3" {
  statement {
    actions = [
      "s3:GetObject"
    ]
    resources = ["arn:aws:s3:::com.smackwerks-kfb/*"]
  }
}

resource "aws_iam_policy" "task_s3" {
  policy = "${data.aws_iam_policy_document.task_s3.json}"
}

resource "aws_iam_role" "task" {
  assume_role_policy = "${data.aws_iam_policy_document.ecs_assume_role.json}"
}

resource "aws_iam_role_policy_attachment" "task" {
  policy_arn = "${aws_iam_policy.task_s3.arn}"
  role = "${aws_iam_role.task.name}"
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

### Compute Cluster
resource "aws_ecs_cluster" "main" {
  name = "${local.project}-cluster"
}

resource "aws_ecs_task_definition" "app" {
  family                   = "${local.project}-app-task"
  task_role_arn            = "${aws_iam_role.task.arn}"
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
  desired_count   = 1
//  desired_count   = "${local.task_count}"
  launch_type     = "FARGATE"

  network_configuration {
    security_groups  = ["${aws_security_group.ecs_tasks.id}"]
    subnets          = ["${local.private_subnets}"]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = "${aws_alb_target_group.app.id}"
    container_name   = "${local.project}-app"
    container_port   = "${local.app_port}"
  }

  depends_on = [
    "aws_alb_listener.front_end",
  ]
}

### Logging

# Set up cloudwatch group and log stream and retain logs for 30 days
resource "aws_cloudwatch_log_group" "kfb" {
  name              = "/ecs/${local.project}-app"
  retention_in_days = 30

  tags {
    Name = "${local.project}-log-group"
  }
}

resource "aws_cloudwatch_log_stream" "kfb" {
  name           = "${local.project}-log-stream"
  log_group_name = "${aws_cloudwatch_log_group.kfb.name}"
}

### Outputs
output "ecr_url" {
  value = "${aws_ecr_repository.kfb.repository_url}"
}

output "alb_domain_name" {
  value = "${aws_alb.main.dns_name}"
}