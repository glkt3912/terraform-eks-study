# EKS復帰手順

## 概要

削除したEKSクラスターを `terraform apply` で完全復元します。

**推定復帰時間**: 15-20分

---

## 前提条件

- ✅ Terraform 1.0以上
- ✅ AWS CLI設定済み（Account ID: 070279951878, Region: ap-northeast-1）
- ✅ kubectl インストール済み
- ✅ helm インストール済み
- ✅ Terraform State保持（`eks/terraform.tfstate`）
- ✅ Git リポジトリ保持

---

## Step 1: ECR/S3のTerraform管理復帰

削除時にState管理から除外したECR/S3を再度インポートします。

### 1.1 ECR Repository インポート

```bash
cd /home/glkt/projects/terraform-eks-study/eks

# ECR Repository
terraform import aws_ecr_repository.demo_app eks-study-demo-app

# ECR Lifecycle Policy
terraform import aws_ecr_lifecycle_policy.demo_app eks-study-demo-app
```

**期待される出力**:
```
aws_ecr_repository.demo_app: Import prepared!
aws_ecr_repository.demo_app: Importing from ID "eks-study-demo-app"...
aws_ecr_repository.demo_app: Import complete!
```

### 1.2 S3 Bucket インポート

```bash
# S3 Bucket名を取得
BUCKET_NAME=$(aws s3 ls | grep eks-study-irsa-test | awk '{print $3}')
echo "Bucket Name: $BUCKET_NAME"

# random_id suffix抽出
SUFFIX=$(echo $BUCKET_NAME | sed 's/eks-study-irsa-test-//')
echo "Suffix: $SUFFIX"

# random_id インポート
terraform import random_id.bucket_suffix $SUFFIX

# S3 Bucket インポート
terraform import aws_s3_bucket.irsa_test $BUCKET_NAME

# S3 Versioning インポート
terraform import aws_s3_bucket_versioning.irsa_test $BUCKET_NAME

# S3 Public Access Block インポート
terraform import aws_s3_bucket_public_access_block.irsa_test $BUCKET_NAME

# S3 Object インポート
terraform import aws_s3_object.test_file "$BUCKET_NAME/test.txt"
```

### 1.3 Import確認

```bash
terraform plan
```

**期待される出力**:
```
No changes. Your infrastructure matches the configuration.
```

もし差分が表示される場合は、軽微な設定差異の可能性があります。
`terraform apply` で同期してください。

---

## Step 2: EKS Cluster再構築

### 2.1 Terraform Apply

```bash
cd /home/glkt/projects/terraform-eks-study/eks

# 事前確認
terraform plan

# リソース作成（約15-20分）
terraform apply -auto-approve
```

**作成されるリソース** （順序）:

| フェーズ | リソース | 所要時間 |
|---------|---------|---------|
| 1 | VPC, Subnets, Route Tables | ~1分 |
| 2 | Internet Gateway, NAT Gateway | ~2分 |
| 3 | Security Groups | ~1分 |
| 4 | IAM Roles/Policies, OIDC Provider | ~1分 |
| 5 | EKS Cluster | ~10分 |
| 6 | EKS Node Group | ~5分 |
| 7 | AWS Load Balancer Controller (Helm) | ~3分 |
| 8 | ArgoCD (Helm) | ~5分 |
| 9 | CloudWatch Log Groups | 即時 |

**合計**: 約15-20分

### 2.2 進捗確認（別ターミナル推奨）

```bash
# EKS Cluster作成状態
watch -n 10 '
echo "=== EKS Cluster Status ==="
aws eks describe-cluster \
  --name eks-study-cluster \
  --region ap-northeast-1 \
  --query "cluster.status" \
  --output text 2>/dev/null || echo "Creating..."
'

# Node Group作成状態
watch -n 10 '
echo "=== Node Group Status ==="
aws eks describe-nodegroup \
  --cluster-name eks-study-cluster \
  --nodegroup-name eks-study-cluster-node-group \
  --region ap-northeast-1 \
  --query "nodegroup.status" \
  --output text 2>/dev/null || echo "Creating..."
'
```

---

## Step 3: kubectl設定

### 3.1 kubeconfig更新

```bash
# kubeconfig設定
aws eks update-kubeconfig \
  --region ap-northeast-1 \
  --name eks-study-cluster

# コンテキスト確認
kubectl config current-context
```

**期待される出力**:
```
Updated context arn:aws:eks:ap-northeast-1:070279951878:cluster/eks-study-cluster in /home/glkt/.kube/config
```

### 3.2 動作確認

```bash
# Node確認
kubectl get nodes

# 期待される出力:
# NAME                                                STATUS   ROLES    AGE   VERSION
# ip-10-0-0-xxx.ap-northeast-1.compute.internal       Ready    <none>   5m    v1.32.x
# ip-10-0-1-xxx.ap-northeast-1.compute.internal       Ready    <none>   5m    v1.32.x

# Pod確認
kubectl get pods -A

# 期待される出力: argocd, kube-system namespace配下のpodが全てRunning
```

---

## Step 4: ArgoCD確認

### 4.1 Admin Password取得

```bash
# パスワード取得
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo
```

**保存してください**: 復帰後は新しいパスワードが発行されます

### 4.2 ArgoCD URL取得

```bash
# Ingress ALB URL取得（約3-5分で有効化）
kubectl get ingress -n argocd argocd-server-ingress \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'; echo
```

**URL例**:
```
k8s-argocd-argocdse-xxxxxxxxxx-yyyyyyyy.ap-northeast-1.elb.amazonaws.com
```

### 4.3 ログイン確認

ブラウザで上記URLにアクセス:

- **Username**: `admin`
- **Password**: Step 4.1で取得したパスワード

**確認ポイント**:
- ✅ ログインできる
- ✅ Applications一覧が表示される
- ✅ `nginx` Application が表示される（OutOfSync状態）
- ✅ `demo-app` Application が表示される（OutOfSync状態）

---

## Step 5: デモアプリデプロイ確認

### 5.1 ArgoCD Applications同期

```bash
# nginx Application同期
kubectl patch application nginx \
  -n argocd \
  --type merge \
  -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}'

# demo-app Application同期
kubectl patch application demo-app \
  -n argocd \
  --type merge \
  -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}'

# 同期状態確認
kubectl get applications -n argocd
```

**期待される出力**:
```
NAME       SYNC STATUS   HEALTH STATUS
demo-app   Synced        Healthy
nginx      Synced        Healthy
```

### 5.2 Pod確認

```bash
# demo-app Pod
kubectl get pods -l app=demo-app

# 期待される出力:
# NAME                        READY   STATUS    RESTARTS   AGE
# demo-app-xxxxxxxx-xxxxx     1/1     Running   0          2m

# nginx Pod（replicas=0なので0個）
kubectl get pods -l app=nginx

# 期待される出力:
# No resources found in default namespace.
```

### 5.3 demo-app動作確認

```bash
# Ingress URL取得
DEMO_URL=$(kubectl get ingress demo-app \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

echo "Demo App URL: http://$DEMO_URL"

# アクセステスト
curl -s http://$DEMO_URL/ | grep -o "<title>.*</title>"
```

**期待される出力**:
```
<title>CI/CD Demo App - EKS Study</title>
```

---

## Step 6: CI/CD再開（オプション）

### 6.1 GitHub Actions有効化

`.github/workflows/ci-cd.yaml` を編集:

```yaml
name: CI/CD Pipeline

on:
  push:
    branches:
      - main
    paths:
      - 'app/**'
  workflow_dispatch:
```

コメントアウトを解除し、"(DISABLED)" を削除。

### 6.2 GitHub Secrets確認

```bash
# Role ARN確認
terraform output github_actions_role_arn

# GitHub Secrets確認
gh secret list
```

**期待される出力**:
```
AWS_ROLE_ARN  Updated 2025-12-01
```

### 6.3 CI/CDテスト

```bash
# テスト変更
cd /home/glkt/projects/terraform-eks-study/app
echo "// Test change $(date)" >> main.go

# コミット & プッシュ
git add main.go
git commit -m "test: verify CI/CD pipeline after restore"
git push

# GitHub Actions確認
gh run list --workflow=ci-cd.yaml --limit 1
```

---

## トラブルシューティング

### エラー1: Terraform Apply失敗（IAM Role）

**症状**:
```
Error: creating EKS Cluster: InvalidParameterException: Role could not be assumed
```

**原因**: IAM Role propagation遅延

**対処**:
```bash
# 30秒待機
sleep 30

# 再実行
terraform apply -auto-approve
```

---

### エラー2: Node Group起動失敗

**症状**:
```
NodeCreationFailure: Instances failed to join the kubernetes cluster
```

**原因**: Security Group設定ミス or subnet問題

**対処**:
```bash
# Node Group削除
terraform destroy -target=aws_eks_node_group.main

# Node Group再作成
terraform apply -target=aws_eks_node_group.main
```

---

### エラー3: ArgoCD Ingress未作成

**症状**: `kubectl get ingress -n argocd` で ADDRESS が空

**原因**: AWS Load Balancer Controller未起動

**対処**:
```bash
# Controller Pod確認
kubectl get pods -n kube-system | grep aws-load-balancer

# ログ確認
kubectl logs -n kube-system deployment/aws-load-balancer-controller

# 再起動
kubectl rollout restart deployment/aws-load-balancer-controller -n kube-system

# 5分待機してIngress再確認
sleep 300
kubectl get ingress -n argocd
```

---

### エラー4: ECR/S3 Import失敗

**症状**:
```
Error: resource not found
```

**原因**: リソース名の誤り or リソースが存在しない

**対処**:
```bash
# ECR Repository名確認
aws ecr describe-repositories --region ap-northeast-1

# S3 Bucket名確認
aws s3 ls | grep eks-study

# 正しい名前で再実行
terraform import aws_ecr_repository.demo_app <正確なリポジトリ名>
```

---

### エラー5: ArgoCD Admin Password取得失敗

**症状**: Secret が存在しない

**原因**: ArgoCD初回起動未完了

**対処**:
```bash
# ArgoCD Pod確認
kubectl get pods -n argocd

# すべてRunningになるまで待機
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s

# パスワード再取得
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo
```

---

## 復帰後のコスト

復帰後は再び月額約$200のコストが発生します。

- EKS Cluster: ~$72/月
- Node Group (t3.medium x2): ~$60/月
- NAT Gateway: ~$30-40/月
- ALB: ~$20/月
- CloudWatch Logs: ~$5-10/月

**使用しない期間は再度削除を推奨**:
```bash
# 再クリーンアップ
cd /home/glkt/projects/terraform-eks-study

# CLEANUP.mdを参照して実行
cat CLEANUP.md
```

---

## チェックリスト

復帰完了後、以下を確認してください:

- [ ] EKS Cluster作成完了
- [ ] Node Group起動完了（2ノード）
- [ ] kubectl接続確認
- [ ] ArgoCD UIログイン成功
- [ ] demo-app Application Synced
- [ ] demo-app Pod Running
- [ ] demo-app Ingress URLアクセス成功
- [ ] GitHub Actions有効化（オプション）

---

## 次のステップ

復帰後は通常のKubernetes運用に戻ります:

1. **アプリケーションデプロイ**: ArgoCD Applicationsを追加
2. **CI/CD実行**: GitHub Actionsで自動デプロイ
3. **監視**: Prometheus + Grafanaのインストール（オプション）
4. **スケーリング**: HPAの有効化（オプション）

詳細は各種ドキュメント（`eks/manifests/*/README.md`）を参照してください。
