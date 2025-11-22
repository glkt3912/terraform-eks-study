# =============================================================================
# Variables
# =============================================================================

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "ap-northeast-1"
}

variable "project_name" {
  description = "Project name (used for resource tagging)"
  type        = string
  default     = "terraform-eks-study"
}

variable "state_bucket_name" {
  description = "S3 bucket name for storing Terraform state (must be globally unique)"
  type        = string
}

variable "lock_table_name" {
  description = "DynamoDB table name for state locking"
  type        = string
  default     = "terraform-state-lock"
}
