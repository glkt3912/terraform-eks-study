# Kubernetes マニフェスト

このディレクトリには、EKSクラスターにアプリケーションをデプロイするためのKubernetesマニフェストファイルが含まれています。

## 前提条件

1. EKSクラスターがデプロイ済みであること（親ディレクトリのTerraformを使用）
2. kubectlがインストール済み
3. AWS CLIが適切な認証情報で設定済み

## kubeconfig の設定

TerraformでEKSクラスターをデプロイした後、kubectlがクラスターに接続できるよう設定します：

```bash
# Terraformの出力からクラスター名を取得
cd ../
terraform output cluster_name

# kubeconfigを更新
aws eks update-kubeconfig \
  --name <cluster-name> \
  --region ap-northeast-1
```

接続確認：

```bash
kubectl cluster-info
kubectl get nodes
```

## 利用可能なマニフェスト

### 基本デプロイメント

#### nginx-deployment.yaml

クラスターの動作確認用のシンプルなNginx Webサーバーデプロイメント。

**構成要素:**

- **Deployment**: Nginx 2レプリカ（nginx:1.27-alpine）
- **Service**: LoadBalancerタイプで外部公開

**リソース:**

- CPU: リクエスト 100m、上限 250m
- メモリ: リクエスト 128Mi、上限 256Mi
- ヘルスチェック: Liveness Probe、Readiness Probe

### 高度な機能

#### hpa/

Horizontal Pod Autoscaler - CPU使用率ベースの自動スケーリング

- **hpa.yaml**: CPU 50%を目標に1-5レプリカでスケーリング
- **load-generator.yaml**: 負荷テスト用Pod
- **README.md**: 詳細な設定とトラブルシューティング

[詳細はこちら](hpa/README.md)

#### ingress/

AWS Load Balancer Controller - ALBによるL7ルーティング

- **ingress.yaml**: nginx用Ingressマニフェスト
- **README.md**: コントローラーのインストール手順

**注意**: Terraform で `ingress-controller.tf` を適用してIAMロールを作成後、Helmでコントローラーをインストールする必要があります。

[詳細はこちら](ingress/README.md)

#### irsa/

IRSA (IAM Roles for Service Accounts) - Pod単位のIAM権限管理

- **service-account.yaml**: IAMロール付きServiceAccount
- **pod-with-irsa.yaml**: S3アクセスのデモPod
- **README.md**: セットアップとテスト手順

**注意**: Terraform で `irsa.tf` と `s3.tf` を適用してIAMロールとS3バケットを作成する必要があります。

[詳細はこちら](irsa/README.md)

#### monitoring/

Prometheus + Grafana - クラスター監視とメトリクス可視化

- **prometheus-values.yaml**: Helm values設定
- **README.md**: インストールとダッシュボード設定

Helmを使用してkube-prometheus-stackをインストールします。

[詳細はこちら](monitoring/README.md)

## サンプルアプリケーションのデプロイ

### 1. Nginxをデプロイ

```bash
kubectl apply -f nginx-deployment.yaml
```

### 2. デプロイ状態の確認

```bash
# Podの確認
kubectl get pods -l app=nginx

# Deploymentの確認
kubectl get deployment nginx-deployment

# Serviceの確認（EXTERNAL-IPが割り当てられるまで待機）
kubectl get svc nginx-service
```

### 3. アプリケーションへのアクセス

LoadBalancerのプロビジョニングを待ちます（2-3分程度）：

```bash
# 外部URLを取得
kubectl get svc nginx-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# または、EXTERNAL-IPが表示されるまで監視
kubectl get svc nginx-service --watch
```

ブラウザまたはcurlでアクセス：

```bash
curl http://<EXTERNAL-IP>
```

Nginxのウェルカムページが表示されます。

### 4. ログの確認

```bash
# Pod名を取得
kubectl get pods -l app=nginx

# ログを表示
kubectl logs <pod-name>

# ログをリアルタイムで追跡
kubectl logs -f <pod-name>
```

### 5. デプロイメントのスケール

```bash
# 3レプリカにスケール
kubectl scale deployment nginx-deployment --replicas=3

# 確認
kubectl get pods -l app=nginx
```

## クリーンアップ

### アプリケーションの削除

```bash
kubectl delete -f nginx-deployment.yaml
```

### 削除の確認

```bash
kubectl get pods -l app=nginx
kubectl get svc nginx-service
```

**注意**: LoadBalancerの削除には数分かかることがあります。`terraform destroy` を実行する前に、AWSコンソールでELBが削除されたことを確認してください。

## トラブルシューティング

### Podが起動しない

```bash
# Podの詳細とイベントを確認
kubectl describe pod <pod-name>

# ノードの状態確認
kubectl get nodes
kubectl describe node <node-name>
```

### LoadBalancerがpendingのまま

```bash
# Serviceのイベントを確認
kubectl describe svc nginx-service

# セキュリティグループがトラフィックを許可しているか確認
# AWSコンソール → EC2 → ロードバランサー で確認
```

### 接続タイムアウト

```bash
# セキュリティグループルールを確認
# EKSクラスターのセキュリティグループがLoadBalancerからのトラフィックを許可している必要があります

# AWSコンソールで確認：
# EC2 → セキュリティグループ → eks-cluster-sg-*
# LoadBalancerのセキュリティグループからのインバウンドルールが必要
```

## クイックスタート: すべての機能を試す

### 1. 基本デプロイメント

```bash
# Nginxをデプロイ
kubectl apply -f nginx-deployment.yaml

# 確認
kubectl get pods,svc -l app=nginx
```

### 2. HPAを有効化

```bash
# HPAを適用
kubectl apply -f hpa/hpa.yaml

# 負荷をかけてスケーリングを確認
kubectl apply -f hpa/load-generator.yaml
kubectl get hpa nginx-hpa --watch
```

### 3. Ingress Controller (オプション)

```bash
# 1. TerraformでIAMロールを作成
cd ../
terraform apply

# 2. HelmでAWS Load Balancer Controllerをインストール
helm repo add eks https://aws.github.io/eks-charts
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName=$(terraform output -raw cluster_name) \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$(terraform output -raw alb_controller_role_arn)

# 3. Ingressを適用
kubectl apply -f manifests/ingress/ingress.yaml
kubectl get ingress
```

### 4. IRSA

```bash
# 1. TerraformでIAMロールとS3バケットを作成（terraform apply済みの場合はスキップ）

# 2. ServiceAccountとPodを適用（ARNとバケット名を置換）
export ROLE_ARN=$(terraform output -raw irsa_s3_role_arn)
export BUCKET_NAME=$(terraform output -raw irsa_test_bucket_name)

sed "s|arn:aws:iam::ACCOUNT_ID:role/PROJECT_NAME-pod-s3-readonly-role|$ROLE_ARN|g" \
  manifests/irsa/service-account.yaml | kubectl apply -f -

cat manifests/irsa/pod-with-irsa.yaml | \
  sed "s|PROJECT_NAME-irsa-test-XXXXXXXX|$BUCKET_NAME|g" | \
  kubectl apply -f -

# 3. ログを確認
kubectl logs irsa-demo
```

### 5. 監視 (Prometheus + Grafana)

```bash
# HelmでPrometheus Stackをインストール
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  -f manifests/monitoring/prometheus-values.yaml

# Grafanaにアクセス
kubectl get svc -n monitoring prometheus-grafana
# LoadBalancerのDNSをブラウザで開く
# Username: admin, Password: admin
```

## 次のステップ

サンプルアプリケーションの動作確認後：

1. 独自のアプリケーションマニフェストを作成
2. ConfigMapとSecretを試す
3. カスタムメトリクスでHPAを設定
4. Prometheusアラートルールを追加
5. EBSで永続ストレージを構成

## 参考リンク

- [HPA詳細](hpa/README.md)
- [Ingress詳細](ingress/README.md)
- [IRSA詳細](irsa/README.md)
- [監視詳細](monitoring/README.md)
