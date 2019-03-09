terraform {
  backend "s3" {
    key    = "kfb/data.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = "${var.region}"
}


locals {
  project = "kfb"
  bucket_name = "com.smackwerks-kfb"
}

resource "aws_s3_bucket" "data" {
  bucket = "${local.bucket_name}"
  acl    = "private"

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  tags = {
    Description = "Data source for ktor-fargate-bench"
    Project = "kfb"
    Name = "KfbDataBucket"
  }
}

resource "aws_ecr_repository" "kfb" {
  name = "com.smackwerks.${local.project}"

  tags {
    Name = "${local.project}-ecr"
    Project = "${local.project}"
  }
}

output "bucket_id" {
  value = "${aws_s3_bucket.data.id}"
}

output "bucket_arn" {
  value = "${aws_s3_bucket.data.arn}"
}

output "bucket_domain_name" {
  value = "${aws_s3_bucket.data.bucket_domain_name}"
}

output "ecr_url" {
  value = "${aws_ecr_repository.kfb.repository_url}"
}

output "ecr_arn" {
  value = "${aws_ecr_repository.kfb.arn}"
}
