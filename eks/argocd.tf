# =============================================================================
# ArgoCD Configuration
# =============================================================================
# GitOps continuous delivery tool for Kubernetes
#
# ArgoCD manages Kubernetes applications declaratively using Git as the
# source of truth. This configuration installs ArgoCD via Helm and sets up
# IRSA for accessing private Git repositories and ECR.
#
# Prerequisites:
# - OIDC provider configured (already done in iam.tf)
# - Helm provider configured (see main.tf)
# - AWS Load Balancer Controller installed (for Ingress)

# -----------------------------------------------------------------------------
# IAM Policy for ArgoCD
# -----------------------------------------------------------------------------
# Permissions for:
# - CodeCommit: Clone private Git repositories
# - ECR: Pull container images
# - Secrets Manager: Access Git credentials

resource "aws_iam_policy" "argocd" {
  name        = "${var.project_name}-ArgoCD-IAMPolicy"
  description = "IAM policy for ArgoCD to access Git repositories and ECR"
  path        = "/"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # CodeCommit read access
      {
        Effect = "Allow"
        Action = [
          "codecommit:GitPull",
          "codecommit:GetBranch",
          "codecommit:GetCommit",
          "codecommit:GetRepository",
          "codecommit:ListBranches",
          "codecommit:ListRepositories"
        ]
        Resource = "arn:aws:codecommit:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      },
      # ECR read access
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:DescribeRepositories",
          "ecr:ListImages"
        ]
        Resource = "*"
      },
      # Secrets Manager (for Git credentials)
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:argocd/*"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-argocd-policy"
  }
}

# -----------------------------------------------------------------------------
# IAM Role for ArgoCD (IRSA)
# -----------------------------------------------------------------------------
# Allows ArgoCD's ServiceAccount to assume this role

locals {
  argocd_namespace       = "argocd"
  argocd_service_account = "argocd-application-controller"
}

resource "aws_iam_role" "argocd" {
  name = "${var.project_name}-eks-argocd-role"

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
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:${local.argocd_namespace}:${local.argocd_service_account}"
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-argocd-role"
  }
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "argocd" {
  policy_arn = aws_iam_policy.argocd.arn
  role       = aws_iam_role.argocd.name
}

# -----------------------------------------------------------------------------
# Kubernetes Namespace for ArgoCD
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = local.argocd_namespace
    labels = {
      name = "argocd"
    }
  }
}

# -----------------------------------------------------------------------------
# ArgoCD Helm Release
# -----------------------------------------------------------------------------

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "7.7.11"
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  # Wait for deployment to complete
  wait          = true
  wait_for_jobs = true
  timeout       = 600 # 10 minutes

  # Values configuration
  values = [
    yamlencode({
      global = {
        domain = "argocd.${var.cluster_name}.local"
      }

      # Configure IRSA for application-controller
      controller = {
        serviceAccount = {
          create = true
          name   = local.argocd_service_account
          annotations = {
            "eks.amazonaws.com/role-arn" = aws_iam_role.argocd.arn
          }
        }
        resources = {
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
          requests = {
            cpu    = "250m"
            memory = "256Mi"
          }
        }
      }

      # Configure IRSA for repo-server (also needs Git access)
      repoServer = {
        serviceAccount = {
          create = true
          name   = "argocd-repo-server"
          annotations = {
            "eks.amazonaws.com/role-arn" = aws_iam_role.argocd.arn
          }
        }
        resources = {
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
          requests = {
            cpu    = "250m"
            memory = "256Mi"
          }
        }
      }

      # Server configuration
      server = {
        # Run in insecure mode (required when behind ALB without TLS)
        extraArgs = [
          "--insecure"
        ]

        # Disable default Ingress (we'll create our own)
        ingress = {
          enabled = false
        }

        # Service type: ClusterIP (will be exposed via Ingress)
        service = {
          type = "ClusterIP"
        }

        # Configure metrics
        metrics = {
          enabled = true
        }

        resources = {
          limits = {
            cpu    = "200m"
            memory = "256Mi"
          }
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
        }
      }

      # Dex for SSO (disabled due to pod capacity constraints)
      dex = {
        enabled = false
      }

      # Redis
      redis = {
        enabled = true
      }

      # ApplicationSet controller (disabled due to pod capacity constraints)
      applicationSet = {
        enabled = false
      }

      # Notifications (disabled due to pod capacity constraints)
      notifications = {
        enabled = false
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.argocd,
    aws_iam_role_policy_attachment.argocd
  ]
}

# -----------------------------------------------------------------------------
# Ingress for ArgoCD Server
# -----------------------------------------------------------------------------
# Exposes ArgoCD UI/API via AWS Load Balancer Controller

resource "kubernetes_ingress_v1" "argocd" {
  metadata {
    name      = "argocd-server-ingress"
    namespace = kubernetes_namespace.argocd.metadata[0].name

    annotations = {
      # AWS Load Balancer Controller annotations
      "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"      = "ip"
      "alb.ingress.kubernetes.io/listen-ports"     = "[{\"HTTP\": 80}]"
      "alb.ingress.kubernetes.io/backend-protocol" = "HTTP"
      "alb.ingress.kubernetes.io/healthcheck-path" = "/healthz"

      # Tags
      "alb.ingress.kubernetes.io/tags" = "Project=${var.project_name},Component=argocd"
    }
  }

  spec {
    ingress_class_name = "alb"

    rule {
      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = "argocd-server"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.argocd
  ]
}

# -----------------------------------------------------------------------------
# Data source to retrieve ArgoCD admin password
# -----------------------------------------------------------------------------

data "kubernetes_secret" "argocd_initial_admin_secret" {
  metadata {
    name      = "argocd-initial-admin-secret"
    namespace = kubernetes_namespace.argocd.metadata[0].name
  }

  depends_on = [
    helm_release.argocd
  ]
}
