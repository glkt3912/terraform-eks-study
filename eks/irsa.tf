# =============================================================================
# IRSA (IAM Roles for Service Accounts) Configuration
# =============================================================================
# Demonstrates Pod-level IAM permissions using IRSA
#
# This example creates an IAM role that allows Pods to read from S3.
# The role is associated with a Kubernetes ServiceAccount.
#
# Prerequisites:
# - OIDC provider configured (already done in iam.tf)
# - Test S3 bucket created (see s3.tf)

locals {
  irsa_namespace       = "default"
  irsa_service_account = "s3-readonly-sa"
}

# -----------------------------------------------------------------------------
# IAM Policy for S3 Read-Only Access
# -----------------------------------------------------------------------------

resource "aws_iam_policy" "pod_s3_readonly" {
  name        = "${var.project_name}-pod-s3-readonly-policy"
  description = "Allow Pods to read from specific S3 bucket"
  path        = "/"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.irsa_test.arn,
          "${aws_s3_bucket.irsa_test.arn}/*"
        ]
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-pod-s3-readonly"
  }
}

# -----------------------------------------------------------------------------
# IAM Role for IRSA
# -----------------------------------------------------------------------------
# This role can be assumed by Pods using the specified ServiceAccount

resource "aws_iam_role" "pod_s3_readonly" {
  name = "${var.project_name}-pod-s3-readonly-role"

  # Trust policy: Allow the ServiceAccount to assume this role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:${local.irsa_namespace}:${local.irsa_service_account}"
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-pod-s3-readonly-role"
  }
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "pod_s3_readonly" {
  policy_arn = aws_iam_policy.pod_s3_readonly.arn
  role       = aws_iam_role.pod_s3_readonly.name
}
