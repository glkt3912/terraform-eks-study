# =============================================================================
# EC2 Module - Variables
# =============================================================================

variable "name" {
  description = "Name prefix for resources"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where EC2 will be deployed (use VPC module output)"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID where EC2 will be deployed (use VPC module output)"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type (t3.micro is free tier eligible in most regions)"
  type        = string
  default     = "t3.micro"
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed for SSH access (recommend restricting to your IP)"
  type        = string
  default     = "0.0.0.0/0"
}
