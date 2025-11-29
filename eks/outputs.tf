# =============================================================================
# Outputs Definition
# =============================================================================

# -----------------------------------------------------------------------------
# VPC Outputs
# -----------------------------------------------------------------------------

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of private subnets"
  value       = aws_subnet.private[*].id
}

# -----------------------------------------------------------------------------
# EKS Cluster Outputs
# -----------------------------------------------------------------------------

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "Endpoint for EKS cluster API server"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data for cluster authentication"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "cluster_version" {
  description = "Kubernetes version of the EKS cluster"
  value       = aws_eks_cluster.main.version
}

output "cluster_arn" {
  description = "ARN of the EKS cluster"
  value       = aws_eks_cluster.main.arn
}

# -----------------------------------------------------------------------------
# OIDC Provider Outputs
# -----------------------------------------------------------------------------

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider for IRSA"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_provider_url" {
  description = "URL of the OIDC provider (without https://)"
  value       = replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")
}

# -----------------------------------------------------------------------------
# Node Group Outputs
# -----------------------------------------------------------------------------

output "node_group_name" {
  description = "Name of the EKS node group"
  value       = aws_eks_node_group.main.node_group_name
}

output "node_group_status" {
  description = "Status of the EKS node group"
  value       = aws_eks_node_group.main.status
}

# -----------------------------------------------------------------------------
# kubectl Configuration
# -----------------------------------------------------------------------------

output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main.name}"
}

# -----------------------------------------------------------------------------
# AWS Load Balancer Controller Outputs
# -----------------------------------------------------------------------------

output "alb_controller_role_arn" {
  description = "ARN of IAM role for AWS Load Balancer Controller"
  value       = aws_iam_role.alb_controller.arn
}

# -----------------------------------------------------------------------------
# IRSA Outputs
# -----------------------------------------------------------------------------

output "irsa_s3_role_arn" {
  description = "ARN of IAM role for S3 read-only access (IRSA example)"
  value       = aws_iam_role.pod_s3_readonly.arn
}

output "irsa_test_bucket_name" {
  description = "Name of S3 bucket for IRSA testing"
  value       = aws_s3_bucket.irsa_test.id
}

# -----------------------------------------------------------------------------
# ArgoCD Outputs
# -----------------------------------------------------------------------------

output "argocd_namespace" {
  description = "Namespace where ArgoCD is installed"
  value       = kubernetes_namespace.argocd.metadata[0].name
}

output "argocd_role_arn" {
  description = "ARN of IAM role for ArgoCD (IRSA)"
  value       = aws_iam_role.argocd.arn
}

output "argocd_server_url" {
  description = "URL to access ArgoCD server (LoadBalancer DNS)"
  value       = try(kubernetes_ingress_v1.argocd.status[0].load_balancer[0].ingress[0].hostname, "Pending...")
}

output "argocd_admin_password" {
  description = "Initial admin password for ArgoCD"
  value       = try(data.kubernetes_secret.argocd_initial_admin_secret.data["password"], "Not yet available")
  sensitive   = true
}

output "argocd_access_instructions" {
  description = "Instructions to access ArgoCD"
  value       = <<-EOT
    ArgoCD Access Instructions:

    1. Get the LoadBalancer URL:
       terraform output argocd_server_url

    2. Get the admin password:
       terraform output -raw argocd_admin_password

       Or directly from Kubernetes:
       kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

    3. Access ArgoCD UI:
       Open browser: http://<LoadBalancer-URL>
       Username: admin
       Password: <from step 2>

    4. CLI Login:
       argocd login <LoadBalancer-URL> --username admin --password <password>

    Note: Change the initial password after first login.
  EOT
}
