terraform {
  backend "s3" {
    key    = "compute.tfstate"
    region = "us-east-1"
  }
}

resource "aws_ecr_repository" "kfb" {
  name = "com.smackwerks.kfb.ecr"
}