# =============================================================================
# VPC Configuration for EKS
# =============================================================================
# Production-ready setup: Multi-AZ + Public/Private Subnets + NAT Gateway
#
# Alternative: See docs/eks/examples/module-vpc.tf for module-based approach

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

data "aws_availability_zones" "available" {
  state = "available"
}

# -----------------------------------------------------------------------------
# VPC
# -----------------------------------------------------------------------------
# DNS hostnames and support are required for EKS

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# -----------------------------------------------------------------------------
# Internet Gateway
# -----------------------------------------------------------------------------
# Gateway for public subnet internet access

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# -----------------------------------------------------------------------------
# Public Subnets (Multi-AZ)
# -----------------------------------------------------------------------------
# Purpose:
# - Host NAT Gateway
# - Host ALB for external access
# - EKS tags for ALB Ingress Controller auto-discovery

resource "aws_subnet" "public" {
  count = 2

  vpc_id            = aws_vpc.main.id
  availability_zone = data.aws_availability_zones.available.names[count.index]

  # CIDR: 10.0.100.0/24, 10.0.101.0/24
  cidr_block = cidrsubnet(var.vpc_cidr, 8, count.index + 100)

  # Auto-assign public IP for public subnet
  map_public_ip_on_launch = true

  tags = {
    Name                                        = "${var.project_name}-public-${data.aws_availability_zones.available.names[count.index]}"
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

# -----------------------------------------------------------------------------
# Private Subnets (Multi-AZ)
# -----------------------------------------------------------------------------
# Purpose:
# - Host EKS nodes (improved security)
# - Internet access via NAT Gateway
# - EKS tags for internal ALB auto-discovery

resource "aws_subnet" "private" {
  count = 2

  vpc_id            = aws_vpc.main.id
  availability_zone = data.aws_availability_zones.available.names[count.index]

  # CIDR: 10.0.0.0/24, 10.0.1.0/24
  cidr_block = cidrsubnet(var.vpc_cidr, 8, count.index)

  tags = {
    Name                                        = "${var.project_name}-private-${data.aws_availability_zones.available.names[count.index]}"
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

# -----------------------------------------------------------------------------
# NAT Gateway
# -----------------------------------------------------------------------------
# Outbound internet access for private subnets
# Note: Costs ~$1/day. Single NAT is sufficient for learning.
# For production, deploy NAT Gateway in each AZ for high availability.

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-nat-eip"
  }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id

  # Place in first public subnet
  subnet_id = aws_subnet.public[0].id

  tags = {
    Name = "${var.project_name}-nat"
  }

  depends_on = [aws_internet_gateway.main]
}

# -----------------------------------------------------------------------------
# Route Tables
# -----------------------------------------------------------------------------

# Public route table
# Route internet traffic to IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count = 2

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private route table
# Route internet traffic to NAT Gateway
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  count = 2

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
