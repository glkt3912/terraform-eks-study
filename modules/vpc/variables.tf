# =============================================================================
# VPC Module - Variables
# =============================================================================

variable "name" {
  description = "Name prefix for resources"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for VPC (e.g., 10.0.0.0/16)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for public subnet (e.g., 10.0.1.0/24)"
  type        = string
  default     = "10.0.1.0/24"
}
