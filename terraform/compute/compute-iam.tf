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
    resources = ["*"]  # TODO: lock down the resources more
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
data "aws_iam_policy_document" "task_s3" {
  statement {
    actions = [
      "s3:GetObject"
    ]
    resources = ["${data.terraform_remote_state.data.bucket_arn}/*"]
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
