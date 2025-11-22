# =============================================================================
# Root Module - Outputs
# =============================================================================
# Aggregate and expose outputs from submodules
# Values displayed after terraform apply

# -----------------------------------------------------------------------------
# VPC Module Outputs
# -----------------------------------------------------------------------------

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = module.vpc.vpc_cidr
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = module.vpc.public_subnet_id
}

# -----------------------------------------------------------------------------
# EC2 Module Outputs
# -----------------------------------------------------------------------------

output "instance_id" {
  description = "ID of the EC2 instance"
  value       = module.ec2.instance_id
}

output "instance_public_ip" {
  description = "Public IP of the EC2 instance"
  value       = module.ec2.instance_public_ip
}

output "instance_public_dns" {
  description = "Public DNS of the EC2 instance"
  value       = module.ec2.instance_public_dns
}

output "security_group_id" {
  description = "ID of the security group"
  value       = module.ec2.security_group_id
}

output "web_url" {
  description = "URL of the web server"
  value       = module.ec2.web_url
}
