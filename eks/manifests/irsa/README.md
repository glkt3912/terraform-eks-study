# IRSA (IAM Roles for Service Accounts)

## 概要

IRSA (IAM Roles for Service Accounts) は、Kubernetes Podに対してAWS IAMロールを安全に割り当てる仕組みです。これにより、Pod単位で細かいIAM権限を制御できます。

## 学習目標

- IRSAの仕組みを理解する
- OIDCプロバイダーの役割を学ぶ
- Pod単位のIAM権限管理を実践する
- セキュリティベストプラクティスを理解する

## アーキテクチャ

```
┌──────────────────────────────────────────────────────────────┐
│ 1. Pod起動時                                                 │
│    ServiceAccount: s3-readonly-sa を指定                    │
└────────────────────────┬─────────────────────────────────────┘
                         │
                         ↓
┌──────────────────────────────────────────────────────────────┐
│ 2. EKSがOIDCトークンを発行                                   │
│    トークンにServiceAccount情報を含める                      │
└────────────────────────┬─────────────────────────────────────┘
                         │
                         ↓
┌──────────────────────────────────────────────────────────────┐
│ 3. AssumeRoleWithWebIdentity                                 │
│    STSにOIDCトークンを送信し、IAMロールを引き受ける          │
└────────────────────────┬─────────────────────────────────────┘
                         │
                         ↓
┌──────────────────────────────────────────────────────────────┐
│ 4. 一時クレデンシャル取得                                    │
│    - AWS_ACCESS_KEY_ID                                       │
│    - AWS_SECRET_ACCESS_KEY                                   │
│    - AWS_SESSION_TOKEN                                       │
└────────────────────────┬─────────────────────────────────────┘
                         │
                         ↓
┌──────────────────────────────────────────────────────────────┐
│ 5. S3バケットへアクセス（読み取り専用）                      │
└──────────────────────────────────────────────────────────────┘
```

## 前提条件

### 1. OIDCプロバイダーの確認

```bash
terraform -chdir=eks output oidc_provider_arn
```

既に `iam.tf` で作成済みです。

## デプロイ手順

### 1. Terraformでリソース作成

```bash
cd eks

# 初期化（random providerを追加したため）
terraform init

# 適用
terraform apply
```

作成されるリソース：
- IAMポリシー: S3バケットへの読み取り専用アクセス
- IAMロール: Podが引き受けるロール（IRSA用）
- S3バケット: テスト用バケット
- S3オブジェクト: test.txt

### 2. IAMロールARNとバケット名を取得

```bash
# IAMロールARNを取得
export ROLE_ARN=$(terraform -chdir=eks output -raw irsa_s3_role_arn)
echo $ROLE_ARN

# S3バケット名を取得
export BUCKET_NAME=$(terraform -chdir=eks output -raw irsa_test_bucket_name)
echo $BUCKET_NAME
```

### 3. ServiceAccountマニフェストを更新

`service-account.yaml` のアノテーションを実際のARNに置き換え：

```bash
# sedで自動置換（Linux/Mac）
sed "s|arn:aws:iam::ACCOUNT_ID:role/PROJECT_NAME-pod-s3-readonly-role|$ROLE_ARN|g" \
  eks/manifests/irsa/service-account.yaml | kubectl apply -f -
```

または手動で編集してから：
```bash
kubectl apply -f eks/manifests/irsa/service-account.yaml
```

### 4. Podマニフェストを更新して適用

```bash
# 環境変数を置換してapply
cat eks/manifests/irsa/pod-with-irsa.yaml | \
  sed "s|PROJECT_NAME-irsa-test-XXXXXXXX|$BUCKET_NAME|g" | \
  kubectl apply -f -
```

### 5. Podのログを確認

```bash
# Podの起動を待つ
kubectl wait --for=condition=Ready pod/irsa-demo --timeout=60s

# ログを確認
kubectl logs irsa-demo
```

期待される出力：
```
=========================================
IRSA Demo: Testing S3 Access
=========================================

1. Checking AWS Identity:
{
    "UserId": "AROAXXXXXXXXXXXXXXXXX:botocore-session-1234567890",
    "Account": "123456789012",
    "Arn": "arn:aws:sts::123456789012:assumed-role/terraform-eks-study-pod-s3-readonly-role/..."
}

2. Listing objects in bucket: terraform-eks-study-irsa-test-a1b2c3d4
2024-11-28 12:34:56       68 test.txt

3. Reading test.txt from S3:
Hello from IRSA! This file demonstrates Pod-level IAM permissions.

4. Attempting to write (should fail):
upload failed: An error occurred (AccessDenied) when calling the PutObject operation
Write denied (expected)

=========================================
IRSA Demo Complete
=========================================
```

### 6. ServiceAccountの確認

```bash
# ServiceAccountを確認
kubectl get serviceaccount s3-readonly-sa -o yaml

# アノテーションが正しく設定されているか確認
kubectl get sa s3-readonly-sa -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'
```

## トラブルシューティング

### S3アクセスが失敗する

**1. IAMロールが正しく設定されているか確認**

```bash
# ServiceAccountのアノテーションを確認
kubectl get sa s3-readonly-sa -o yaml

# IAMロールが存在するか確認
aws iam get-role --role-name terraform-eks-study-pod-s3-readonly-role
```

**2. Trust Policyが正しいか確認**

```bash
# Trust Policyを確認
aws iam get-role --role-name terraform-eks-study-pod-s3-readonly-role \
  --query 'Role.AssumeRolePolicyDocument'
```

**3. Pod内の環境変数を確認**

```bash
# Podにアクセス
kubectl exec -it irsa-demo -- /bin/sh

# 環境変数を確認
env | grep AWS

# 期待される環境変数:
# AWS_ROLE_ARN=arn:aws:iam::123456789012:role/...
# AWS_WEB_IDENTITY_TOKEN_FILE=/var/run/secrets/eks.amazonaws.com/serviceaccount/token
```

### "AccessDenied" エラー

**解決策**:

```bash
# IAMポリシーがアタッチされているか確認
aws iam list-attached-role-policies \
  --role-name terraform-eks-study-pod-s3-readonly-role

# バケット名を再確認
terraform -chdir=eks output irsa_test_bucket_name
```

## IRSAなしのPodとの比較

IRSAの効果を確認するため、IRSAなしのPodを起動：

```bash
kubectl run no-irsa-demo --image=amazon/aws-cli:2.15.10 \
  --command -- /bin/sh -c "aws sts get-caller-identity 2>&1 || echo 'No credentials'; sleep infinity"

# ログを確認
kubectl logs no-irsa-demo
```

期待される出力：
```
Unable to locate credentials.
No credentials
```

**結論**: IRSAなしではAWS APIにアクセスできません。

## クリーンアップ

```bash
# Podを削除
kubectl delete pod irsa-demo no-irsa-demo

# ServiceAccountを削除
kubectl delete serviceaccount s3-readonly-sa

# Terraformリソースを削除
cd eks
terraform destroy -target=aws_s3_object.test_file
terraform destroy -target=aws_s3_bucket.irsa_test
terraform destroy -target=aws_iam_role.pod_s3_readonly
terraform destroy -target=aws_iam_policy.pod_s3_readonly
```

## コスト

| リソース | 料金 |
|---------|------|
| OIDC Provider | 無料 |
| IAM Role/Policy | 無料 |
| STS API呼び出し | 無料 |
| S3バケット | ほぼ無料（テストファイル1個のみ） |

**推定**: 実質0円

## 参考リンク

- [EKS IRSA公式ドキュメント](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [IAMロールとServiceAccountの関連付け](https://docs.aws.amazon.com/eks/latest/userguide/specify-service-account-role.html)
