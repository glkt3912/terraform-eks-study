# AWS Load Balancer Controller & Ingress

## 概要

AWS Load Balancer Controllerは、Kubernetes IngressリソースをAWS Application Load Balancer (ALB)に変換するコントローラーです。従来のLoadBalancer Serviceと比べて、以下の利点があります：

- **コスト削減**: 複数のサービスを1つのALBで共有可能
- **高度なルーティング**: パスベース、ホストベースのルーティング
- **SSL/TLS終端**: ACM証明書の統合
- **AWS統合**: WAF、Shield、Cognito統合

## 学習目標

- Ingressリソースの理解
- ALBとTarget Groupの関係
- パスベースルーティングの実装
- IRSA（IAM Roles for Service Accounts）の実践

## アーキテクチャ

```
┌──────────────┐
│   Internet   │
└──────┬───────┘
       │
       ↓
┌──────────────────────┐
│ Application Load     │ ← AWS Load Balancer Controller が作成
│ Balancer (ALB)       │
└──────┬───────────────┘
       │
       ↓
┌──────────────────────┐
│ Target Group         │ ← nginx Podを登録
│ (IP mode)            │
└──────┬───────────────┘
       │
       ↓
┌──────────────────────┐
│ nginx Pods           │ ← 直接アクセス（NodePort不要）
│ (in EKS cluster)     │
└──────────────────────┘
```

### target-typeの違い

| target-type | 説明 | メリット | デメリット |
|-------------|------|----------|------------|
| **ip** | Pod IPを直接登録 | 効率的、ヘルスチェック正確 | ENI制限に注意 |
| **instance** | ノードIPを登録 | 互換性高い | NodePort必要、非効率 |

## 前提条件

### 1. Terraformでリソース作成

```bash
cd eks
terraform init
terraform plan
terraform apply
```

これにより以下が作成されます：
- IAMポリシー: `AWSLoadBalancerControllerIAMPolicy`
- IAMロール: `eks-alb-controller-role`（IRSA用）

### 2. VPCサブネットのタグ確認

ALBが正しいサブネットを検出するために必要なタグ：

**パブリックサブネット**（internet-facingのALB用）:
```
kubernetes.io/role/elb = 1
kubernetes.io/cluster/<cluster-name> = shared
```

**プライベートサブネット**（internalのALB用）:
```
kubernetes.io/role/internal-elb = 1
kubernetes.io/cluster/<cluster-name> = shared
```

確認コマンド：
```bash
aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$(terraform output -raw vpc_id)" \
  --query 'Subnets[*].[SubnetId,Tags[?Key==`Name`].Value|[0],Tags[?Key==`kubernetes.io/role/elb`].Value|[0]]' \
  --output table
```

**注意**: 本プロジェクトのvpc.tfで既にタグは設定済みです。

### 3. IAMロールARNの取得

```bash
cd eks
terraform output alb_controller_role_arn
```

出力例：
```
arn:aws:iam::123456789012:role/terraform-eks-study-eks-alb-controller-role
```

## AWS Load Balancer Controllerのインストール

### 方法1: Helmでインストール（推奨）

```bash
# Helm リポジトリを追加
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# クラスター名を取得
export CLUSTER_NAME=$(terraform -chdir=eks output -raw cluster_name)

# IAMロールARNを取得
export ALB_ROLE_ARN=$(terraform -chdir=eks output -raw alb_controller_role_arn)

# AWS Load Balancer Controllerをインストール
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName=$CLUSTER_NAME \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$ALB_ROLE_ARN \
  --set region=$(terraform -chdir=eks output -raw aws_region) \
  --set vpcId=$(terraform -chdir=eks output -raw vpc_id)
```

### 方法2: kubectlでインストール

cert-managerが必要です：

```bash
# cert-managerをインストール
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# コントローラーのマニフェストをダウンロード
curl -Lo controller.yaml https://github.com/kubernetes-sigs/aws-load-balancer-controller/releases/latest/download/v2_7_2_full.yaml

# クラスター名を編集（手動）
# Deployment内の --cluster-name=your-cluster-name を修正

# ServiceAccountのアノテーションを編集
# eks.amazonaws.com/role-arn: <IAM_ROLE_ARN>

# 適用
kubectl apply -f controller.yaml
```

## インストール確認

```bash
# Podが起動しているか確認
kubectl get deployment -n kube-system aws-load-balancer-controller

# 期待される出力
NAME                           READY   UP-TO-DATE   AVAILABLE   AGE
aws-load-balancer-controller   2/2     2            2           1m

# ログを確認
kubectl logs -n kube-system deployment/aws-load-balancer-controller
```

成功メッセージ例：
```
{"level":"info","msg":"Reconciling targetGroupBinding"}
{"level":"info","msg":"controller started","controller":"ingress"}
```

## Ingressのデプロイ

### 1. nginx-serviceが存在することを確認

```bash
kubectl get service nginx-service
```

なければ、先にnginx-deploymentを適用：
```bash
kubectl apply -f eks/manifests/nginx-deployment.yaml
```

### 2. Ingressを適用

```bash
kubectl apply -f ingress.yaml
```

### 3. ALB作成を確認

```bash
# Ingressの状態を確認
kubectl get ingress nginx-ingress

# ALBのDNS名が表示されるまで2-3分かかります
NAME            CLASS    HOSTS   ADDRESS                                                                   PORTS   AGE
nginx-ingress   <none>   *       k8s-default-nginxing-abc123-1234567890.ap-northeast-1.elb.amazonaws.com   80      2m
```

### 4. ブラウザでアクセス

```bash
# ALBのDNS名を取得
export ALB_DNS=$(kubectl get ingress nginx-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "http://$ALB_DNS"

# curlでテスト
curl http://$ALB_DNS
```

正常に動作すれば、nginxのウェルカムページが表示されます。

### 5. AWS ConsoleでALBを確認

```bash
# ブラウザで開く
echo "https://ap-northeast-1.console.aws.amazon.com/ec2/home?region=ap-northeast-1#LoadBalancers:"
```

確認項目：
- ロードバランサー名: `k8s-default-nginxing-...`
- ターゲットグループ: Pod IPが登録されている
- ヘルスチェック: healthy状態

## トラブルシューティング

### Ingressが作成されない

```bash
# コントローラーのログを確認
kubectl logs -n kube-system deployment/aws-load-balancer-controller --tail=50

# イベントを確認
kubectl describe ingress nginx-ingress
```

**よくあるエラー**:

1. **サブネットが見つからない**
   ```
   Error: unable to resolve at least 2 subnets
   ```

   **解決策**: サブネットにタグを追加
   ```bash
   aws ec2 create-tags \
     --resources subnet-xxx subnet-yyy \
     --tags Key=kubernetes.io/role/elb,Value=1
   ```

2. **IAM権限不足**
   ```
   Error: AccessDenied when calling CreateLoadBalancer
   ```

   **解決策**: IAMポリシーが正しくアタッチされているか確認
   ```bash
   aws iam list-attached-role-policies \
     --role-name terraform-eks-study-eks-alb-controller-role
   ```

3. **ServiceAccountが正しくない**
   ```bash
   kubectl get sa aws-load-balancer-controller -n kube-system -o yaml
   ```

   アノテーションに`eks.amazonaws.com/role-arn`があるか確認

### ALBが作成されるが接続できない

1. **セキュリティグループを確認**

   ALBのセキュリティグループがポート80を許可しているか：
   ```bash
   aws ec2 describe-security-groups \
     --filters "Name=tag:elbv2.k8s.aws/cluster,Values=<cluster-name>" \
     --query 'SecurityGroups[*].[GroupId,IpPermissions]'
   ```

2. **ターゲットの健全性を確認**

   AWS Console → ターゲットグループ → Targets タブ
   - Status が "healthy" になっているか
   - unhealthyの場合、ヘルスチェック設定を確認

3. **Podが実行中か確認**
   ```bash
   kubectl get pods -l app=nginx
   ```

### ALBが削除されない

Ingressを削除してもALBが残る場合：

```bash
# ファイナライザーを確認
kubectl get ingress nginx-ingress -o yaml | grep finalizers

# 手動で削除（最終手段）
kubectl patch ingress nginx-ingress -p '{"metadata":{"finalizers":[]}}' --type=merge
kubectl delete ingress nginx-ingress
```

その後、AWS Consoleから手動でALBを削除。

## 高度な設定

### HTTPS（SSL/TLS）の有効化

ACM証明書を使用：

```yaml
metadata:
  annotations:
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:region:account:certificate/xxx
    alb.ingress.kubernetes.io/ssl-redirect: "443"
```

### 複数サービスへのルーティング

```yaml
spec:
  rules:
  - host: api.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: api-service
            port:
              number: 8080
  - host: www.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-service
            port:
              number: 80
```

### Internal ALB（VPC内部のみ）

```yaml
metadata:
  annotations:
    alb.ingress.kubernetes.io/scheme: internal
```

## クリーンアップ

```bash
# Ingressを削除（ALBも自動削除される）
kubectl delete -f ingress.yaml

# コントローラーをアンインストール（Helm使用時）
helm uninstall aws-load-balancer-controller -n kube-system

# Terraformリソースを削除
cd eks
terraform destroy -target=aws_iam_role.alb_controller
terraform destroy -target=aws_iam_policy.alb_controller
```

**注意**: Ingressを削除すると、ALBも自動的に削除されます（約2-3分）。

## コスト

| リソース | 料金 | 備考 |
|---------|------|------|
| ALB | $0.0243/時間 | 約$0.58/日 |
| LCU | $0.008/LCU/時間 | トラフィック量による |
| データ転送 | 従量課金 | アウトバウンドのみ |

**推定**: 低トラフィックで約$0.60〜$1.00/日

## 次のステップ

- **WAF統合**: Webアプリケーションファイアウォール
- **Cognito統合**: 認証・認可
- **カスタムドメイン**: Route 53との統合
- **複数Ingress**: 環境ごとのALB分離

## 参考リンク

- [AWS Load Balancer Controller公式](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [Ingressアノテーション一覧](https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.7/guide/ingress/annotations/)
- [トラブルシューティングガイド](https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.7/deploy/troubleshooting/)
