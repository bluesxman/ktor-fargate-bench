provider "aws" {
  region = "${var.region}"
}

# Fetch AZs in the current region
data "aws_availability_zones" "available" {}

locals {
  project = "kfb"
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags {
    Name = "${local.project}-vpc"
    Project = "${local.project}"
  }
}

# Create var.az_count private subnets, each in a different AZ
resource "aws_subnet" "private" {
  count             = "${var.az_count}"
  cidr_block        = "${cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)}"
  availability_zone = "${data.aws_availability_zones.available.names[count.index]}"
  vpc_id            = "${aws_vpc.main.id}"

  tags {
    Name = "${local.project}-private-${count.index}"
    Project = "${local.project}"
  }
}

# Create var.az_count public subnets, each in a different AZ
resource "aws_subnet" "public" {
  count                   = "${var.az_count}"
  cidr_block              = "${cidrsubnet(aws_vpc.main.cidr_block, 8, var.az_count + count.index)}"
  availability_zone       = "${data.aws_availability_zones.available.names[count.index]}"
  vpc_id                  = "${aws_vpc.main.id}"
  map_public_ip_on_launch = true

  tags {
    Name = "${local.project}-public-${count.index}"
    Project = "${local.project}"
  }
}

# IGW for the public subnet
resource "aws_internet_gateway" "gw" {
  vpc_id = "${aws_vpc.main.id}"

  tags {
    Name = "${local.project}-igw"
    Project = "${local.project}"
  }
}

# Route the public subnet trafic through the IGW
resource "aws_route" "internet_access" {
  route_table_id         = "${aws_vpc.main.main_route_table_id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.gw.id}"
}

# Create a NAT gateway with an EIP for each private subnet to get internet connectivity
resource "aws_eip" "gw" {
  count      = "${var.az_count}"
  vpc        = true
  depends_on = ["aws_internet_gateway.gw"]

  tags {
    Name = "${local.project}-eip-${count.index}"
    Project = "${local.project}"
  }
}

resource "aws_nat_gateway" "gw" {
  count         = "${var.az_count}"
  subnet_id     = "${element(aws_subnet.public.*.id, count.index)}"
  allocation_id = "${element(aws_eip.gw.*.id, count.index)}"

  tags {
    Name = "${local.project}-nat-${count.index}"
    Project = "${local.project}"
  }
}

# Create a new route table for the private subnets, make it route non-local traffic through the NAT gateway to the internet
resource "aws_route_table" "private" {
  count  = "${var.az_count}"
  vpc_id = "${aws_vpc.main.id}"

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = "${element(aws_nat_gateway.gw.*.id, count.index)}"
  }

  tags {
    Name = "${local.project}-private-route-table-${count.index}"
    Project = "${local.project}"
  }
}

# Explicitly associate the newly created route tables to the private subnets (so they don't default to the main route table)
resource "aws_route_table_association" "private" {
  count          = "${var.az_count}"
  subnet_id      = "${element(aws_subnet.private.*.id, count.index)}"
  route_table_id = "${element(aws_route_table.private.*.id, count.index)}"
}