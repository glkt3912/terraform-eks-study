# =============================================================================
# ECR (Elastic Container Registry) Configuration
# =============================================================================
# Container image repository for CI/CD pipeline
#
# This ECR repository stores Docker images built by GitHub Actions.
# Images are tagged with Git commit SHA for traceability.

# -----------------------------------------------------------------------------
# ECR Repository
# -----------------------------------------------------------------------------

resource "aws_ecr_repository" "demo_app" {
  name                 = "${var.project_name}-demo-app"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name        = "${var.project_name}-demo-app"
    Environment = "study"
    ManagedBy   = "terraform"
  }
}

# -----------------------------------------------------------------------------
# ECR Lifecycle Policy
# -----------------------------------------------------------------------------
# Keep only recent images to save storage costs

resource "aws_ecr_lifecycle_policy" "demo_app" {
  repository = aws_ecr_repository.demo_app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus     = "any"
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "ecr_repository_url" {
  description = "URL of ECR repository"
  value       = aws_ecr_repository.demo_app.repository_url
}

output "ecr_repository_arn" {
  description = "ARN of ECR repository"
  value       = aws_ecr_repository.demo_app.arn
}
