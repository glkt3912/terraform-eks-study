# =============================================================================
# EKS Managed Node Group Configuration
# =============================================================================
# Managed Node Group: AWS manages AMI updates and scaling
#
# Node type comparison:
# | Type               | Management | Cost   | Flexibility |
# |--------------------|------------|--------|-------------|
# | Managed Node Group | AWS        | Medium | Medium      |
# | Self-managed Nodes | Self       | Low    | High        |
# | Fargate            | AWS        | High   | Low         |
#
# Alternatives:
# - Module-based: See docs/eks/examples/module-eks.tf
# - Fargate: See docs/eks/examples/fargate-profile.tf
# - Launch Template: See docs/eks/examples/launch-template.tf

# -----------------------------------------------------------------------------
# EKS Managed Node Group
# -----------------------------------------------------------------------------

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.cluster_name}-node-group"
  node_role_arn   = aws_iam_role.eks_node_group.arn

  # Place in private subnets for improved security
  subnet_ids = aws_subnet.private[*].id

  # Instance configuration
  instance_types = var.node_instance_types

  # Capacity type: ON_DEMAND (standard) or SPOT (cost reduction)
  capacity_type = var.node_capacity_type

  # Scaling configuration
  scaling_config {
    min_size     = var.node_min_size
    max_size     = var.node_max_size
    desired_size = var.node_desired_size
  }

  # Update configuration (max_unavailable: nodes unavailable during update)
  update_config {
    max_unavailable = 1
  }

  # Disk size (GB)
  disk_size = 20

  # Kubernetes labels (used for Pod scheduling)
  labels = {
    role = "general"
  }

  # Wait for IAM role policy attachments
  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_ecr_policy,
  ]

  tags = {
    Name = "${var.cluster_name}-node-group"
  }

  # Ignore desired_size changes (may be modified by autoscaler)
  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

# For optional configurations, see docs/eks/examples/:
# - Launch Template: launch-template.tf
# - Fargate Profile: fargate-profile.tf
