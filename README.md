# Terraform + EKS Study

AWS + Terraform + Kubernetes(EKS) 学習プロジェクト

## 目的

- AWS に慣れる
- Terraform でインフラ構築に慣れる
- Kubernetes (EKS) を触れる
- 無料枠 + $100 クレジット内で完了させる

## ディレクトリ構成

```text
.
├── prerequisites/     # 事前準備・環境確認
├── basics/            # Week1: VPC + EC2 基礎
├── modules/           # Week2-3: Terraform モジュール化
├── eks/               # Week4-5: EKS 構築
│   └── manifests/     # Kubernetes マニフェスト
└── docs/              # 学習メモ (gitignore)
```

## 学習ロードマップ

| Week | 内容 | コスト目安 |
|------|------|-----------|
| 1 | AWS基礎 + Terraform EC2/VPC | $0-2 |
| 2 | ローカルK8s + Terraformモジュール化 | $0-3 |
| 3 | Terraform state管理 (S3 backend) | $1-2 |
| 4-5 | EKS構築 | $15-25 |
| 6 | アプリデプロイ + 破棄 | $5-10 |

## セットアップ

### 1. 環境確認

```bash
./prerequisites/check-tools.sh
```

### 2. AWS認証設定

```bash
aws configure
# Access Key ID: <your-key>
# Secret Access Key: <your-secret>
# Region: ap-northeast-1
# Output format: json
```

### 3. Terraform 実行

```bash
cd basics/
terraform init
terraform plan
terraform apply
```

### 4. リソース削除 (重要)

```bash
terraform destroy
```

## コスト管理

- **請求アラート設定必須**: $50, $80 で通知
- **使わない日は `terraform destroy`**
- NAT Gateway は高コスト、学習時は避ける
- Spot Instance 活用でコスト削減可能

## 注意事項

- `terraform.tfvars` は機密情報を含むため git 管理外
- `*.tfstate` はリソース状態を含むため git 管理外
- 本番環境では S3 backend + DynamoDB locking 推奨
