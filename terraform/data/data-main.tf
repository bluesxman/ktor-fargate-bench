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

  tags = {
      Description = "Data source for ktor-fargate-bench"
      Project = "ktor-fargate-bench"
  }
}