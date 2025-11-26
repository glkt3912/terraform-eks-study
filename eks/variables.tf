# =============================================================================
# Variables Definition
# =============================================================================

# -----------------------------------------------------------------------------
# General
# -----------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "ap-northeast-1"
}

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "eks-study"
}

# -----------------------------------------------------------------------------
# VPC
# -----------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

# -----------------------------------------------------------------------------
# EKS Cluster
# -----------------------------------------------------------------------------

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "eks-study-cluster"
}

variable "kubernetes_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.32"

  validation {
    condition     = can(regex("^1\\.(3[0-4])$", var.kubernetes_version))
    error_message = "Kubernetes version must be 1.30, 1.31, 1.32, 1.33, or 1.34"
  }
}

# -----------------------------------------------------------------------------
# Node Group
# -----------------------------------------------------------------------------

variable "node_instance_types" {
  description = "List of instance types for EKS node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_capacity_type" {
  description = "Capacity type for node group (ON_DEMAND or SPOT)"
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "Capacity type must be ON_DEMAND or SPOT"
  }
}

variable "node_min_size" {
  description = "Minimum number of nodes in node group"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of nodes in node group"
  type        = number
  default     = 3
}

variable "node_desired_size" {
  description = "Desired number of nodes in node group"
  type        = number
  default     = 2
}
