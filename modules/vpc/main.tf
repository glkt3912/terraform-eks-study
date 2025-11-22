# =============================================================================
# VPC Module
# =============================================================================
# This module creates the following resources:
# - VPC
# - Public Subnet
# - Internet Gateway
# - Route Table + Association

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

data "aws_availability_zones" "available" {
  state = "available"
}

# -----------------------------------------------------------------------------
# VPC
# -----------------------------------------------------------------------------
# VPC is a virtual network space on AWS
# enable_dns_hostnames: Assign DNS hostnames to EC2 instances
# enable_dns_support: Enable DNS resolution within VPC

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.name}-vpc"
  }
}

# -----------------------------------------------------------------------------
# Internet Gateway
# -----------------------------------------------------------------------------
# IGW enables communication between VPC and the internet
# Required for public subnet to access the internet

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name}-igw"
  }
}

# -----------------------------------------------------------------------------
# Public Subnet
# -----------------------------------------------------------------------------
# map_public_ip_on_launch: Auto-assign public IP to instances in this subnet
# availability_zone: Use the first available AZ

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.name}-public-subnet"
  }
}

# -----------------------------------------------------------------------------
# Route Table
# -----------------------------------------------------------------------------
# Route table defines traffic routing within the subnet
# 0.0.0.0/0 -> IGW: Route all external traffic to internet via IGW

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.name}-public-rt"
  }
}

# Associate subnet with route table
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}
