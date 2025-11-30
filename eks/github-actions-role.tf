# =============================================================================
# GitHub Actions IAM Role (OIDC)
# =============================================================================
# Allows GitHub Actions to push images to ECR without long-lived credentials
#
# This uses OpenID Connect (OIDC) federation to allow GitHub Actions
# workflows to assume an IAM role and access AWS resources securely.

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# -----------------------------------------------------------------------------
# OIDC Provider for GitHub Actions
# -----------------------------------------------------------------------------

resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  thumbprint_list = [
    data.tls_certificate.github.certificates[0].sha1_fingerprint
  ]

  tags = {
    Name      = "${var.project_name}-github-actions-oidc"
    ManagedBy = "terraform"
  }
}

# -----------------------------------------------------------------------------
# IAM Policy for GitHub Actions
# -----------------------------------------------------------------------------
# Permissions needed for CI/CD pipeline

resource "aws_iam_policy" "github_actions" {
  name        = "${var.project_name}-GitHubActions-Policy"
  description = "Policy for GitHub Actions to push to ECR"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # ECR access
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeRepositories",
          "ecr:ListImages"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-github-actions-policy"
  }
}

# -----------------------------------------------------------------------------
# IAM Role for GitHub Actions
# -----------------------------------------------------------------------------

locals {
  github_repo = "glkt3912/terraform-eks-study"
}

resource "aws_iam_role" "github_actions" {
  name = "${var.project_name}-github-actions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github_actions.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${local.github_repo}:*"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-github-actions-role"
  }
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "github_actions" {
  policy_arn = aws_iam_policy.github_actions.arn
  role       = aws_iam_role.github_actions.name
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "github_actions_role_arn" {
  description = "ARN of IAM role for GitHub Actions (add this to GitHub Secrets as AWS_ROLE_ARN)"
  value       = aws_iam_role.github_actions.arn
}
