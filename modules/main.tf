# =============================================================================
# Root Module - Compose infrastructure using submodules
# =============================================================================
# This file calls vpc and ec2 submodules to build
# the complete infrastructure

terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # Apply common tags to all resources
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = "study"
      ManagedBy   = "terraform"
    }
  }
}

# -----------------------------------------------------------------------------
# VPC Module
# -----------------------------------------------------------------------------
# Build network foundation
# Output values (vpc_id, public_subnet_id) are used by EC2 module

module "vpc" {
  source = "./vpc"

  name               = var.project_name
  vpc_cidr           = var.vpc_cidr
  public_subnet_cidr = var.public_subnet_cidr
}

# -----------------------------------------------------------------------------
# EC2 Module
# -----------------------------------------------------------------------------
# Deploy EC2 using VPC module outputs
# Reference other module outputs via: module.<module_name>.<output_name>

module "ec2" {
  source = "./ec2"

  name             = var.project_name
  vpc_id           = module.vpc.vpc_id           # Reference VPC module output
  subnet_id        = module.vpc.public_subnet_id # Reference VPC module output
  instance_type    = var.instance_type
  allowed_ssh_cidr = var.allowed_ssh_cidr
}
