# EKS復帰用情報

## バックアップ情報

- **実行日**: 2025-12-01
- **実行者**: glkt
- **ブランチ**: feat/cleanup-and-restore
- **AWS Account ID**: 070279951878
- **AWS Region**: ap-northeast-1

---

## 保持リソース情報

### ECR Repository

**Repository Name**: `eks-study-demo-app`

**確認コマンド**:
```bash
aws ecr describe-repositories \
  --repository-names eks-study-demo-app \
  --region ap-northeast-1 \
  --query 'repositories[0].repositoryUri' \
  --output text
```

**最新イメージタグ**: `6f9cbea9f8cbe05fdf4d977df5f944564b00b55e`

**イメージ一覧確認**:
```bash
aws ecr list-images \
  --repository-name eks-study-demo-app \
  --region ap-northeast-1 \
  --query 'imageIds[*].imageTag' \
  --output table
```

---

### S3 Bucket

**Bucket Name Prefix**: `eks-study-irsa-test-`

**確認コマンド**:
```bash
aws s3 ls | grep eks-study-irsa-test
```

**バケット内容確認**:
```bash
BUCKET=$(aws s3 ls | grep eks-study-irsa-test | awk '{print $3}')
aws s3 ls s3://$BUCKET/
```

---

### ArgoCD認証情報

- **Admin Username**: `admin`
- **Admin Password**: `FbTrEi2ZIUqc3E7-`
  - 注: 初回デプロイ時に自動生成されるため、復帰後は新しいパスワードが発行されます

**復帰後のパスワード取得**:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo
```

---

### Terraform State

- **Location**: `/home/glkt/projects/terraform-eks-study/eks/terraform.tfstate`
- **Backup Location**: `/home/glkt/projects/terraform-eks-study/backup/terraform-state/`
- **Version**: Terraform 1.6.6
- **Serial**: 84

**State確認**:
```bash
cd /home/glkt/projects/terraform-eks-study/eks
terraform state list | wc -l
```

---

## 削除前のクラスター構成

### EKS Cluster

- **Cluster Name**: `eks-study-cluster`
- **Kubernetes Version**: 1.32
- **Endpoint**: `https://5775B24A6D7B745B1EFB55F9CF7DE797.gr7.ap-northeast-1.eks.amazonaws.com`
- **OIDC Provider**: `oidc.eks.ap-northeast-1.amazonaws.com/id/5775B24A6D7B745B1EFB55F9CF7DE797`

### Node Group

- **Node Group Name**: `eks-study-cluster-node-group`
- **Instance Type**: t3.medium
- **Desired Capacity**: 2
- **Min Size**: 1
- **Max Size**: 3
- **Disk Size**: 20GB
- **AMI Type**: AL2_x86_64

### ネットワーク構成

- **VPC CIDR**: `10.0.0.0/16`
- **Public Subnets**: `10.0.100.0/24`, `10.0.101.0/24`
- **Private Subnets**: `10.0.0.0/24`, `10.0.1.0/24`
- **NAT Gateway**: 1台 (Public Subnet 0)
- **Internet Gateway**: 1台

### Helm Releases

#### AWS Load Balancer Controller
- **Chart Version**: 1.10.2 (Terraform managed)
- **Namespace**: kube-system
- **Service Account**: aws-load-balancer-controller

#### ArgoCD
- **Chart Version**: 7.7.11 (Terraform managed)
- **Namespace**: argocd
- **URL**: `k8s-argocd-argocdse-b7776dbdbb-317330130.ap-northeast-1.elb.amazonaws.com`

### デプロイ済みアプリケーション

#### nginx (ArgoCD管理)
- **Replicas**: 0 (scaled down)
- **Image**: nginx:1.27-alpine
- **ArgoCD Application**: `nginx`

#### demo-app (ArgoCD管理)
- **Replicas**: 1
- **Image**: `070279951878.dkr.ecr.ap-northeast-1.amazonaws.com/eks-study-demo-app:6f9cbea9f8cbe05fdf4d977df5f944564b00b55e`
- **Port**: 8080
- **Ingress URL**: `k8s-default-demoapp-6d4c89c707-401133571.ap-northeast-1.elb.amazonaws.com`
- **ArgoCD Application**: `demo-app`

---

## GitHub Secrets

- **AWS_ROLE_ARN**: `arn:aws:iam::070279951878:role/eks-study-github-actions-role`

**確認コマンド**:
```bash
gh secret list
```

---

## IAM Roles

### EKS Cluster Role
- **Role Name**: `eks-study-eks-cluster-role`
- **Policy**: `AmazonEKSClusterPolicy`

### EKS Node Role
- **Role Name**: `eks-study-eks-node-role`
- **Policies**:
  - `AmazonEKSWorkerNodePolicy`
  - `AmazonEKS_CNI_Policy`
  - `AmazonEC2ContainerRegistryReadOnly`

### ArgoCD IRSA Role
- **Role Name**: `eks-study-eks-argocd-role`
- **Permissions**: CodeCommit, ECR, Secrets Manager

### ALB Controller IRSA Role
- **Role Name**: `eks-study-eks-alb-controller-role`
- **Permissions**: ALB/NLB management

### GitHub Actions Role
- **Role Name**: `eks-study-github-actions-role`
- **Permissions**: ECR push

### S3 ReadOnly Role
- **Role Name**: `eks-study-pod-s3-readonly-role`
- **Permissions**: S3 read-only

---

## 復帰に必要な情報

復帰時は以下を参照：
- **削除手順**: `CLEANUP.md`
- **復帰手順**: `RESTORE.md`
- **Terraform定義**: `eks/*.tf`

---

## コスト情報

### 削除前の月額コスト
- EKS Cluster: ~$72/月
- Node Group (t3.medium x2): ~$60/月
- NAT Gateway: ~$30-40/月
- ALB: ~$20/月
- CloudWatch Logs: ~$5-10/月
- **合計**: ~$200/月

### 削除後の月額コスト
- ECR Repository: ~$0.10/月
- S3 Bucket: ~$0.02/月
- **合計**: ~$1/月

**削減額**: ~$199/月 (~$2,388/年)
