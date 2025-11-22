# =============================================================================
# Outputs
# =============================================================================
# Use these values to configure backend in other Terraform configurations

output "state_bucket_name" {
  description = "Name of the S3 bucket for Terraform state"
  value       = aws_s3_bucket.tfstate.id
}

output "state_bucket_arn" {
  description = "ARN of the S3 bucket for Terraform state"
  value       = aws_s3_bucket.tfstate.arn
}

output "lock_table_name" {
  description = "Name of the DynamoDB table for state locking"
  value       = aws_dynamodb_table.tfstate_lock.name
}

output "lock_table_arn" {
  description = "ARN of the DynamoDB table for state locking"
  value       = aws_dynamodb_table.tfstate_lock.arn
}

output "backend_config" {
  description = "Backend configuration to add to other Terraform configurations"
  value       = <<-EOT
    # Add this to your terraform block:
    backend "s3" {
      bucket         = "${aws_s3_bucket.tfstate.id}"
      key            = "<environment>/terraform.tfstate"  # Change per environment
      region         = "${var.aws_region}"
      dynamodb_table = "${aws_dynamodb_table.tfstate_lock.name}"
      encrypt        = true
    }
  EOT
}
