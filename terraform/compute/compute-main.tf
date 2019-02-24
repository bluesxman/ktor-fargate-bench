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
}

resource "aws_ecr_repository" "kfb" {
  name = "com.smackwerks.kfb.ecr"

  tags {
    Name = "${local.project}-ecr"
    Project = "${local.project}"
  }
}

output "ecr_url" {
  value = "${aws_ecr_repository.kfb.repository_url}"
}