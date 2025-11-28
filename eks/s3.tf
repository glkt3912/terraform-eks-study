# =============================================================================
# S3 Bucket for IRSA Testing
# =============================================================================
# Test bucket to demonstrate Pod-level IAM permissions
#
# This bucket is used to verify that Pods with IRSA can access S3,
# while Pods without IRSA cannot.

# Random suffix for unique bucket name
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# -----------------------------------------------------------------------------
# S3 Bucket
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "irsa_test" {
  bucket = "${var.project_name}-irsa-test-${random_id.bucket_suffix.hex}"

  # Force destroy (safe for learning environment)
  force_destroy = true

  tags = {
    Name        = "${var.project_name}-irsa-test"
    Environment = "study"
    Purpose     = "IRSA demonstration"
  }
}

# -----------------------------------------------------------------------------
# Bucket Versioning (Disabled for simplicity)
# -----------------------------------------------------------------------------

resource "aws_s3_bucket_versioning" "irsa_test" {
  bucket = aws_s3_bucket.irsa_test.id

  versioning_configuration {
    status = "Disabled"
  }
}

# -----------------------------------------------------------------------------
# Block Public Access (Security best practice)
# -----------------------------------------------------------------------------

resource "aws_s3_bucket_public_access_block" "irsa_test" {
  bucket = aws_s3_bucket.irsa_test.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# -----------------------------------------------------------------------------
# Sample Object (For testing read access)
# -----------------------------------------------------------------------------

resource "aws_s3_object" "test_file" {
  bucket  = aws_s3_bucket.irsa_test.id
  key     = "test.txt"
  content = "Hello from IRSA! This file demonstrates Pod-level IAM permissions."

  content_type = "text/plain"

  tags = {
    Name = "IRSA test file"
  }
}
