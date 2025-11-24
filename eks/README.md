# EKS Cluster Configuration

本番寄りの EKS クラスター構成。各リソースに代替方法（terraform-aws-modules）をコメントで併記。

## Architecture

```
                    ┌─────────────────────────────────────────────────┐
                    │                     VPC                         │
                    │                  10.0.0.0/16                    │
                    │                                                 │
                    │  ┌─────────────────┐  ┌─────────────────┐      │
                    │  │  Public Subnet  │  │  Public Subnet  │      │
                    │  │  10.0.100.0/24  │  │  10.0.101.0/24  │      │
                    │  │     (AZ-a)      │  │     (AZ-c)      │      │
Internet ◄──────────┼──┤   NAT Gateway   │  │                 │      │
     ▲              │  └────────┬────────┘  └─────────────────┘      │
     │              │           │                                     │
     │ IGW          │  ┌────────▼────────┐  ┌─────────────────┐      │
     │              │  │ Private Subnet  │  │ Private Subnet  │      │
     │              │  │  10.0.0.0/24    │  │  10.0.1.0/24    │      │
     │              │  │     (AZ-a)      │  │     (AZ-c)      │      │
     │              │  │                 │  │                 │      │
     │              │  │  ┌───────────┐  │  │  ┌───────────┐  │      │
     │              │  │  │EKS Node   │  │  │  │EKS Node   │  │      │
     │              │  │  └───────────┘  │  │  └───────────┘  │      │
     │              │  └─────────────────┘  └─────────────────┘      │
     │              │                                                 │
     │              │        ┌─────────────────────────┐             │
     │              │        │    EKS Control Plane    │             │
kubectl ◄───────────┼────────┤    (AWS Managed)        │             │
                    │        └─────────────────────────┘             │
                    └─────────────────────────────────────────────────┘
```

## Files Structure

| File | Description |
|------|-------------|
| `main.tf` | EKS クラスター、セキュリティグループ、ログ設定 |
| `vpc.tf` | VPC、サブネット、NAT Gateway、ルートテーブル |
| `iam.tf` | IAM ロール、ポリシー、OIDC プロバイダー |
| `node_group.tf` | マネージドノードグループ |
| `variables.tf` | 変数定義 |
| `outputs.tf` | 出力定義 |

## Design Decisions

### 1. VPC

| 判断 | 理由 | 代替案 |
|------|------|--------|
| マルチ AZ | 高可用性確保 | シングル AZ（コスト削減） |
| プライベートサブネット | ノードを直接公開しない | パブリックのみ（簡易構成） |
| NAT Gateway x1 | コスト削減 | AZ ごとに配置（本番推奨） |

**モジュール代替:**

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"
  # 詳細は vpc.tf のコメント参照
}
```

### 2. IAM

| 判断 | 理由 | 代替案 |
|------|------|--------|
| OIDC Provider | IRSA で Pod 単位の権限管理 | ノードロールに権限付与 |
| マネージドポリシー | シンプル、AWS 管理 | カスタムポリシー |

**IRSA (IAM Roles for Service Accounts):**

- Pod に最小権限を付与できる
- ノード全体への権限付与より安全
- AWS Load Balancer Controller 等で必須

### 3. EKS Cluster

| 判断 | 理由 | 代替案 |
|------|------|--------|
| Public + Private endpoint | kubectl アクセス + VPC 内通信 | Private only（VPN必須） |
| CloudWatch Logs (api, audit, auth) | 監査・トラブルシュート | 全ログ or 無効化 |
| Kubernetes 1.31 | 最新安定版 | LTS バージョン |

**モジュール代替:**

```hcl
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"
  # 詳細は main.tf のコメント参照
}
```

### 4. Node Group

| 判断 | 理由 | 代替案 |
|------|------|--------|
| Managed Node Group | AWS 管理で運用負荷軽減 | Self-managed / Fargate |
| t3.medium | 学習用途で十分 | t3.large（本番） |
| ON_DEMAND | 安定性重視 | SPOT（コスト70%削減） |
| min=1, max=3, desired=2 | スケーリング柔軟性 | 固定数 |

## Cost Estimate

| Resource | Cost/Day (USD) |
|----------|----------------|
| EKS Cluster | ~$2.40 |
| EC2 (t3.medium x2) | ~$1.50 |
| NAT Gateway | ~$1.00 |
| CloudWatch Logs | ~$0.10 |
| **Total** | **~$5.00** |

**コスト削減オプション:**

- `node_capacity_type = "SPOT"` で約70%削減
- NAT Gateway を必要時のみ作成
- ノード数を最小限に
- 使わない時は `terraform destroy`

## Usage

### 1. Setup

```bash
cd eks/
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars as needed
```

### 2. Deploy

```bash
terraform init
terraform plan
terraform apply
```

### 3. Configure kubectl

```bash
aws eks update-kubeconfig --region ap-northeast-1 --name eks-study-cluster
kubectl get nodes
```

### 4. Destroy

```bash
terraform destroy
```

## Alternative: Using terraform-aws-modules

本構成は学習目的で各リソースを個別に定義。
実務では `terraform-aws-modules` の使用を推奨。

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"
  # ...
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"
  # ...
}
```

**メリット:**

- コード量削減（500行 → 100行）
- ベストプラクティス組み込み済み
- コミュニティでメンテナンス
- バグ修正・セキュリティ更新が早い

**デメリット:**

- 内部実装がブラックボックス
- カスタマイズに制限あり
- モジュールバージョンアップ時の影響

## Next Steps

1. **アプリデプロイ**: `manifests/` にサンプルアプリを配置
2. **Ingress 設定**: AWS Load Balancer Controller のインストール
3. **監視**: CloudWatch Container Insights / Prometheus
4. **CI/CD**: ArgoCD / Flux でGitOps
