# =============================================================================
# EKS Cluster Configuration
# =============================================================================
# Production-ready setup: Security Groups + CloudWatch Logs + Endpoint Access
#
# Alternative: See docs/eks/examples/module-eks.tf for module-based approach

# -----------------------------------------------------------------------------
# Terraform Configuration
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = "study"
      ManagedBy   = "terraform"
    }
  }
}

# -----------------------------------------------------------------------------
# EKS Cluster
# -----------------------------------------------------------------------------

resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    # Place in private subnets for improved security
    subnet_ids = aws_subnet.private[*].id

    # Endpoint access configuration
    # - public: Access via internet (kubectl)
    # - private: Access from within VPC only
    # For production, private-only is recommended (via VPN/Direct Connect)
    endpoint_public_access  = true
    endpoint_private_access = true

    security_group_ids = [aws_security_group.eks_cluster.id]
  }

  # CloudWatch Logs configuration (be mindful of costs)
  # - api: Kubernetes API server logs
  # - audit: Audit logs (who did what)
  # - authenticator: Authentication logs
  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator"
  ]

  # Upgrade policy (EXTENDED incurs additional cost)
  upgrade_policy {
    support_type = "STANDARD"
  }

  # Wait for IAM role policy attachment
  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]

  tags = {
    Name = var.cluster_name
  }
}

# -----------------------------------------------------------------------------
# EKS Cluster Security Group
# -----------------------------------------------------------------------------
# Controls communication between control plane and worker nodes

resource "aws_security_group" "eks_cluster" {
  name        = "${var.cluster_name}-cluster-sg"
  description = "Security group for EKS cluster control plane"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.cluster_name}-cluster-sg"
  }
}

# Control plane to node communication (443)
resource "aws_vpc_security_group_egress_rule" "eks_cluster_to_node" {
  security_group_id = aws_security_group.eks_cluster.id
  description       = "Allow control plane to communicate with worker nodes"

  referenced_security_group_id = aws_security_group.eks_node.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}

# Control plane to node communication (kubelet)
resource "aws_vpc_security_group_egress_rule" "eks_cluster_to_node_kubelet" {
  security_group_id = aws_security_group.eks_cluster.id
  description       = "Allow control plane to communicate with kubelet"

  referenced_security_group_id = aws_security_group.eks_node.id
  from_port                    = 10250
  to_port                      = 10250
  ip_protocol                  = "tcp"
}

# -----------------------------------------------------------------------------
# EKS Node Security Group
# -----------------------------------------------------------------------------
# Security group for worker nodes

resource "aws_security_group" "eks_node" {
  name        = "${var.cluster_name}-node-sg"
  description = "Security group for EKS worker nodes"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name                                        = "${var.cluster_name}-node-sg"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

# Node from control plane communication
resource "aws_vpc_security_group_ingress_rule" "node_from_cluster" {
  security_group_id = aws_security_group.eks_node.id
  description       = "Allow worker nodes to receive communication from control plane"

  referenced_security_group_id = aws_security_group.eks_cluster.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}

# Node to node communication (for Pod networking)
resource "aws_vpc_security_group_ingress_rule" "node_to_node" {
  security_group_id = aws_security_group.eks_node.id
  description       = "Allow nodes to communicate with each other"

  referenced_security_group_id = aws_security_group.eks_node.id

  # All protocols
  ip_protocol = "-1"
}

# Kubelet communication
resource "aws_vpc_security_group_ingress_rule" "node_kubelet" {
  security_group_id = aws_security_group.eks_node.id
  description       = "Allow kubelet communication from control plane"

  referenced_security_group_id = aws_security_group.eks_cluster.id
  from_port                    = 10250
  to_port                      = 10250
  ip_protocol                  = "tcp"
}

# Outbound traffic (ECR, S3, API server access)
resource "aws_vpc_security_group_egress_rule" "node_outbound" {
  security_group_id = aws_security_group.eks_node.id
  description       = "Allow all outbound traffic"

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

# -----------------------------------------------------------------------------
# CloudWatch Log Group for EKS
# -----------------------------------------------------------------------------
# Store EKS logs (manage costs via retention)

resource "aws_cloudwatch_log_group" "eks" {
  name = "/aws/eks/${var.cluster_name}/cluster"

  # Short retention for learning (cost reduction)
  retention_in_days = 7

  tags = {
    Name = "${var.cluster_name}-logs"
  }
}
