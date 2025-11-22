# =============================================================================
# EC2 Module
# =============================================================================
# This module creates the following resources:
# - Security Group (SSH + HTTP)
# - EC2 Instance (with Apache HTTPD installed)

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

# Get the latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# -----------------------------------------------------------------------------
# Security Group
# -----------------------------------------------------------------------------
# Security group acts as a firewall controlling traffic to instances
# Ingress: Inbound rules / Egress: Outbound rules

resource "aws_security_group" "this" {
  name        = "${var.name}-web-sg"
  description = "Security group for web server"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name}-web-sg"
  }
}

# Allow SSH access (port 22)
# Recommend restricting source IP via allowed_ssh_cidr
resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.this.id
  description       = "SSH access"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = var.allowed_ssh_cidr

  tags = {
    Name = "${var.name}-ssh-ingress"
  }
}

# Allow HTTP access (port 80)
# For web server access
resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.this.id
  description       = "HTTP access"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"

  tags = {
    Name = "${var.name}-http-ingress"
  }
}

# Allow all outbound traffic
# Required for internet access from instance (dnf update, etc.)
resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.this.id
  description       = "Allow all outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = {
    Name = "${var.name}-all-egress"
  }
}

# -----------------------------------------------------------------------------
# EC2 Instance
# -----------------------------------------------------------------------------
# metadata_options: Enforce IMDSv2 (security best practice)
# user_data: Startup script (installs Apache HTTPD)

resource "aws_instance" "this" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.this.id]
  user_data_replace_on_change = true

  # Enforce IMDSv2 (Instance Metadata Service v2)
  # http_tokens = "required" disables IMDSv1
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # Startup script: Install and start Apache HTTPD
  user_data = <<-EOF
    #!/bin/bash
    dnf update -y
    dnf install -y httpd
    systemctl start httpd
    systemctl enable httpd
    echo "<h1>Hello from Terraform Module!</h1><p>Instance: $(hostname)</p>" > /var/www/html/index.html
  EOF

  tags = {
    Name = "${var.name}-web"
  }
}
