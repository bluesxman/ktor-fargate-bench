terraform {
  backend "s3" {
    key    = "kfb/compute.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region  = var.region
}

### Imports
data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = local.backend_bucket
    key    = "${local.project}/network.tfstate"
    region = var.region
  }
}

data "terraform_remote_state" "data" {
  backend = "s3"

  config = {
    bucket = local.backend_bucket
    key    = "${local.project}/data.tfstate"
    region = var.region
  }
}

locals {
  project         = "kfb"
  backend_bucket  = "com.smackwerks-tfstate"
  vpc_id          = data.terraform_remote_state.network.outputs.vpc_id
  public_subnets  = data.terraform_remote_state.network.outputs.public_subnet_ids
  private_subnets = data.terraform_remote_state.network.outputs.private_subnet_ids
  task_count      = length(local.public_subnets)
  app_image       = "${data.terraform_remote_state.data.outputs.ecr_url}:latest"
  task_cpu        = 2048
  task_memory     = 4096
  app_port        = 8080 # The port inside the docker container that the app is listening on
  elb_port        = 80   # The port that the ALB is listening on
  service_name    = "${local.project}-service"

  # TODO: Test removing hostPort in the port mappings
  # TODO: Import the logging resources from data
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

### Compute Cluster
resource "aws_ecs_cluster" "main" {
  name = "${local.project}-cluster"
}

resource "aws_ecs_task_definition" "app" {
  family                   = "${local.project}-app-task"
  task_role_arn            = aws_iam_role.task.arn
  execution_role_arn       = aws_iam_role.task_execution.arn
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = local.task_cpu
  memory                   = local.task_memory
  container_definitions    = local.task_def
}

resource "aws_ecs_service" "main" {
  name            = local.service_name
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1

  //  desired_count   = "${local.task_count}"
  launch_type = "FARGATE"

  network_configuration {
    security_groups = [aws_security_group.ecs_tasks.id]
    subnets          = local.private_subnets
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_alb_target_group.app.id
    container_name   = "${local.project}-app"
    container_port   = local.app_port
  }

  depends_on = [aws_alb_listener.front_end]
}

### Outputs
output "alb_domain_name" {
  value = aws_alb.main.dns_name
}

