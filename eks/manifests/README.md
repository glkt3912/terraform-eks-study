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

### nginx-deployment.yaml

クラスターの動作確認用のシンプルなNginx Webサーバーデプロイメント。

**構成要素:**
- **Deployment**: Nginx 2レプリカ（nginx:1.27-alpine）
- **Service**: LoadBalancerタイプで外部公開

**リソース:**
- CPU: リクエスト 100m、上限 250m
- メモリ: リクエスト 128Mi、上限 256Mi
- ヘルスチェック: Liveness Probe、Readiness Probe

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

## 次のステップ

サンプルアプリケーションの動作確認後：

1. 独自のアプリケーションマニフェストを作成
2. ConfigMapとSecretを試す
3. IngressでHTTPルーティングを実装
4. Horizontal Pod Autoscaler (HPA)を設定
5. EBSで永続ストレージを構成
