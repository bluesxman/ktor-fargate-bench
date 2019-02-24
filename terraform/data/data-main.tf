terraform {
  backend "s3" {
    key    = "data.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = "${var.region}"
}


locals {
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
  }
}