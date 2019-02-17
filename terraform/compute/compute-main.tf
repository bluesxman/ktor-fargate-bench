terraform {
  backend "s3" {
    key    = "compute.tfstate"
    region = "us-east-1"
  }
}