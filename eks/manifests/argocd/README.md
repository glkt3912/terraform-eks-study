# ArgoCD GitOps デプロイメント

## 概要

ArgoCDは、Kubernetes向けの宣言的GitOps継続デリバリーツールです。Gitリポジトリを信頼できる唯一の情報源（Single Source of Truth）として、Kubernetesアプリケーションを自動的にデプロイ・管理します。

**GitOpsの原則**:
- **宣言的**: すべての設定をGitで管理
- **バージョン管理**: 変更履歴が明確
- **自動同期**: Gitの変更を自動検知してデプロイ
- **監査可能**: 誰が何をいつ変更したかが追跡可能

## 学習目標

- GitOpsの概念と利点の理解
- ArgoCDの基本操作（UI / CLI）
- Applicationリソースの作成と管理
- 自動同期と手動同期の違い
- Terraformによる完全なIaC管理の実践

## アーキテクチャ

```
┌─────────────────────────────────────────────────────────────┐
│                        GitOps Workflow                       │
└─────────────────────────────────────────────────────────────┘

┌──────────────┐           ┌──────────────────┐
│              │           │                  │
│  Developer   │  git push │  Git Repository  │
│              ├──────────>│  (GitHub/GitLab) │
│              │           │                  │
└──────────────┘           └────────┬─────────┘
                                    │
                                    │ ① Poll / Webhook
                                    │
                                    ↓
                           ┌──────────────────┐
                           │                  │
                           │     ArgoCD       │
                           │  (in EKS cluster)│
                           │                  │
                           └────────┬─────────┘
                                    │
                                    │ ② Apply manifests
                                    │
                                    ↓
                           ┌──────────────────┐
                           │                  │
                           │  Kubernetes API  │
                           │                  │
                           └────────┬─────────┘
                                    │
                                    │ ③ Deploy
                                    │
                                    ↓
                           ┌──────────────────┐
                           │                  │
                           │   Applications   │
                           │   (Pods/Services)│
                           │                  │
                           └──────────────────┘
```

### ArgoCDコンポーネント

| コンポーネント | 役割 | 備考 |
|-------------|------|------|
| **application-controller** | Gitリポジトリを監視し、同期を管理 | IRSA設定済み |
| **repo-server** | Gitリポジトリからmanifestを取得 | IRSA設定済み |
| **server** | Web UI / API サーバー | HTTP-only（--insecure） |
| **redis** | キャッシュとメッセージング | 必須 |
| **dex** | SSO（Single Sign-On） | 無効化（容量制約） |
| **applicationset** | 複数Applicationの一括管理 | 無効化（容量制約） |
| **notifications** | 通知機能 | 無効化（容量制約） |

## 前提条件

### 1. Terraformで構築済みのリソース

本プロジェクトでは、ArgoCDは完全にTerraformで管理されています：

```bash
cd eks
terraform apply
```

これにより以下が作成されます：
- **IAMポリシー**: CodeCommit、ECR、Secrets Managerへのアクセス権限
- **IAMロール**: IRSA用（`eks-study-eks-argocd-role`）
- **Kubernetes Namespace**: `argocd`
- **Helm Release**: ArgoCD（v7.7.11）
- **Ingress**: ALB経由での外部アクセス

### 2. ArgoCD情報の取得

```bash
# ArgoCD Server URL（ALBのDNS名）
terraform output argocd_server_url

# 管理者パスワード
terraform output -raw argocd_admin_password

# アクセス手順の表示
terraform output argocd_access_instructions
```

## アクセス方法

### Web UIへのアクセス

```bash
# 1. URLとパスワードを取得
export ARGOCD_URL=$(terraform output -raw argocd_server_url)
export ARGOCD_PASSWORD=$(terraform output -raw argocd_admin_password)

echo "ArgoCD URL: http://$ARGOCD_URL"
echo "Username: admin"
echo "Password: $ARGOCD_PASSWORD"

# 2. ブラウザで開く
open "http://$ARGOCD_URL"  # macOS
# xdg-open "http://$ARGOCD_URL"  # Linux
```

ログイン情報：
- **Username**: `admin`
- **Password**: `terraform output -raw argocd_admin_password` で取得

### ArgoCD CLIのインストール

```bash
# macOS (Homebrew)
brew install argocd

# Linux
curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x /usr/local/bin/argocd

# バージョン確認
argocd version --client
```

### CLIでログイン

```bash
# ArgoCD サーバーにログイン
export ARGOCD_URL=$(terraform output -raw argocd_server_url)
export ARGOCD_PASSWORD=$(terraform output -raw argocd_admin_password)

argocd login $ARGOCD_URL \
  --username admin \
  --password $ARGOCD_PASSWORD \
  --insecure

# ログイン確認
argocd account get-user-info
```

**注意**: `--insecure` は学習環境用（HTTP-only）の設定です。本番環境ではHTTPSを使用してください。

## 基本的な使い方

### 1. サンプルアプリケーションのデプロイ

ArgoCD公式のguestbookアプリで動作確認：

#### Web UIでの作成

1. ArgoCD UIにログイン
2. 「+ New App」をクリック
3. 以下の情報を入力：

```yaml
Application Name: guestbook
Project: default
Sync Policy: Manual

Repository URL: https://github.com/argoproj/argocd-example-apps.git
Path: guestbook
Revision: HEAD

Cluster: https://kubernetes.default.svc
Namespace: default
```

4. 「CREATE」をクリック
5. アプリケーションカードが表示されたら「SYNC」→「SYNCHRONIZE」

#### CLIでの作成

```bash
argocd app create guestbook \
  --repo https://github.com/argoproj/argocd-example-apps.git \
  --path guestbook \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace default

# 同期（デプロイ）
argocd app sync guestbook

# 状態確認
argocd app get guestbook
```

#### デプロイ確認

```bash
# ArgoCD Application状態
kubectl get applications -n argocd

# デプロイされたリソース
kubectl get all -n default -l app.kubernetes.io/instance=guestbook

# 期待される出力
NAME                                READY   STATUS    RESTARTS   AGE
pod/guestbook-ui-85985d774c-xxxxx   1/1     Running   0          1m
```

### 2. 既存のnginxをArgoCD管理に移行

現在kubectlで管理しているnginxをGitOpsに移行する手順：

#### Step 1: manifestをGitリポジトリに配置

```bash
# 既存のmanifestをエクスポート
kubectl get deployment nginx-deployment -o yaml > nginx-deployment.yaml
kubectl get service nginx-service -o yaml > nginx-service.yaml
kubectl get ingress nginx-ingress -o yaml > nginx-ingress.yaml

# Gitリポジトリにコミット
git add nginx-*.yaml
git commit -m "Add nginx manifests for ArgoCD"
git push
```

#### Step 2: ArgoCD Applicationを作成

```bash
argocd app create nginx \
  --repo https://github.com/<your-username>/terraform-eks-study.git \
  --path eks/manifests/nginx \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace default \
  --sync-policy automated \
  --self-heal \
  --auto-prune
```

**重要なオプション**:
- `--sync-policy automated`: Gitの変更を自動検知してデプロイ
- `--self-heal`: Kubernetesで手動変更があった場合、Gitの状態に戻す
- `--auto-prune`: Gitから削除されたリソースをKubernetesからも削除

#### Step 3: GitOpsワークフローの体験

```bash
# 1. manifestを編集（例：replicas を3に変更）
vim nginx-deployment.yaml
# replicas: 3

# 2. コミット&プッシュ
git commit -am "Scale nginx to 3 replicas"
git push

# 3. ArgoCD が自動で同期（約3分以内）
argocd app get nginx --refresh

# 4. Podが3つに増えたことを確認
kubectl get pods -l app=nginx
```

## ArgoCD CLI コマンド集

### Application管理

```bash
# Application一覧
argocd app list

# Application詳細
argocd app get <app-name>

# Application作成
argocd app create <app-name> \
  --repo <git-repo-url> \
  --path <path-in-repo> \
  --dest-server <k8s-server> \
  --dest-namespace <namespace>

# Application同期（デプロイ）
argocd app sync <app-name>

# Application削除
argocd app delete <app-name>

# リソースの差分確認
argocd app diff <app-name>

# 同期履歴
argocd app history <app-name>

# ロールバック
argocd app rollback <app-name> <history-id>
```

### Repository管理

```bash
# リポジトリ追加
argocd repo add https://github.com/user/repo.git \
  --username <username> \
  --password <password>

# プライベートリポジトリ（SSH）
argocd repo add git@github.com:user/repo.git \
  --ssh-private-key-path ~/.ssh/id_rsa

# リポジトリ一覧
argocd repo list

# リポジトリ削除
argocd repo rm https://github.com/user/repo.git
```

### Cluster管理

```bash
# クラスタ一覧
argocd cluster list

# クラスタ追加
argocd cluster add <context-name>

# クラスタ削除
argocd cluster rm <cluster-url>
```

### Project管理

```bash
# プロジェクト一覧
argocd proj list

# プロジェクト作成
argocd proj create <project-name>

# プロジェクトにリポジトリを許可
argocd proj add-source <project-name> <repo-url>

# プロジェクトにクラスタを許可
argocd proj add-destination <project-name> <cluster-url> <namespace>
```

### その他

```bash
# 同期状態の確認（全Application）
argocd app list --refresh

# ログ表示
argocd app logs <app-name>

# Pod内のコンテナログ
argocd app logs <app-name> --container <container-name>

# パスワード変更
argocd account update-password

# バージョン確認
argocd version
```

## Application Manifest（YAML定義）

CLIの代わりに、ApplicationをYAMLで定義することも可能：

```yaml
# manifests/argocd/example-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nginx
  namespace: argocd
spec:
  # Gitリポジトリ情報
  source:
    repoURL: https://github.com/user/repo.git
    targetRevision: HEAD
    path: manifests/nginx

  # デプロイ先
  destination:
    server: https://kubernetes.default.svc
    namespace: default

  # 同期ポリシー
  syncPolicy:
    automated:
      prune: true      # Gitから削除されたリソースを自動削除
      selfHeal: true   # 手動変更を自動で戻す
      allowEmpty: false
    syncOptions:
      - CreateNamespace=true

  # プロジェクト
  project: default
```

適用：
```bash
kubectl apply -f manifests/argocd/example-app.yaml
```

## トラブルシューティング

### Applicationが同期されない

```bash
# Application状態の確認
argocd app get <app-name>

# イベントログ
argocd app get <app-name> --show-operation

# リポジトリ接続確認
argocd repo get <repo-url>
```

**よくあるエラー**:

1. **リポジトリ認証失敗**
   ```
   Error: authentication required
   ```

   **解決策**: 認証情報を再設定
   ```bash
   argocd repo add https://github.com/user/repo.git \
     --username <username> \
     --password <personal-access-token>
   ```

2. **manifest解析エラー**
   ```
   Error: error validating data
   ```

   **解決策**: YAMLファイルの構文を確認
   ```bash
   kubectl apply --dry-run=client -f <manifest-file>
   ```

3. **権限不足**
   ```
   Error: forbidden: User "system:serviceaccount:argocd:argocd-application-controller" cannot create resource
   ```

   **解決策**: ServiceAccount に適切な RBAC 権限を付与

### Podが起動しない

```bash
# ArgoCD Podの状態確認
kubectl get pods -n argocd

# ログ確認
kubectl logs -n argocd deployment/argocd-server
kubectl logs -n argocd deployment/argocd-application-controller
kubectl logs -n argocd deployment/argocd-repo-server

# イベント確認
kubectl get events -n argocd --sort-by='.lastTimestamp'
```

### UI/CLIにログインできない

```bash
# パスワードをリセット
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# または、新しいパスワードを設定
argocd account update-password \
  --current-password <old-password> \
  --new-password <new-password>
```

### IRSA（IAM権限）の問題

```bash
# ServiceAccountにIAMロールが付与されているか確認
kubectl get sa argocd-application-controller -n argocd -o yaml | grep role-arn

# 期待される出力
eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/eks-study-eks-argocd-role

# Pod環境変数の確認
kubectl exec -n argocd deployment/argocd-application-controller -- env | grep AWS

# 期待される出力
AWS_ROLE_ARN=arn:aws:iam::xxx:role/eks-study-eks-argocd-role
AWS_WEB_IDENTITY_TOKEN_FILE=/var/run/secrets/eks.amazonaws.com/serviceaccount/token
```

## 高度な設定

### 自動同期ポリシー

```yaml
spec:
  syncPolicy:
    automated:
      prune: true        # 自動削除
      selfHeal: true     # 自動修復
    retry:
      limit: 5           # 失敗時のリトライ回数
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

### Sync Waves（デプロイ順序制御）

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "1"  # 小さい数字から順にデプロイ
```

例：
- Wave 0: Namespace、ConfigMap
- Wave 1: Deployment
- Wave 2: Service、Ingress

### Health Check カスタマイズ

```yaml
spec:
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/replicas  # replicasの差分を無視（HPA使用時）
```

### Helm Chartのデプロイ

```yaml
spec:
  source:
    repoURL: https://charts.bitnami.com/bitnami
    chart: nginx
    targetRevision: 13.2.23
    helm:
      values: |
        replicaCount: 3
        service:
          type: LoadBalancer
```

### Kustomizeの使用

```yaml
spec:
  source:
    repoURL: https://github.com/user/repo.git
    path: overlays/production
    targetRevision: HEAD
    kustomize:
      namePrefix: prod-
      commonLabels:
        env: production
```

### プライベートリポジトリ（CodeCommit）

IRSA設定済みのため、追加の認証情報不要：

```bash
argocd repo add https://git-codecommit.ap-northeast-1.amazonaws.com/v1/repos/my-app \
  --type git \
  --name my-app-repo
```

ArgoCDのIAMロールには、すでにCodeCommit読み取り権限が付与されています。

### ECRプライベートイメージ

IRSA設定済みのため、追加の認証情報不要：

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  template:
    spec:
      containers:
        - name: app
          image: 123456789012.dkr.ecr.ap-northeast-1.amazonaws.com/my-app:latest
```

ArgoCDのIAMロールには、すでにECR読み取り権限が付与されています。

## セキュリティ

### パスワードの変更

初期パスワードは必ず変更してください：

```bash
# Web UI: User Info → Update Password

# CLI:
argocd account update-password
```

### RBAC（ロールベースアクセス制御）

```bash
# 新しいユーザーを追加
argocd account list
argocd account update-password --account <username>

# ロールの確認
argocd proj role list <project-name>
```

### SSO（将来の拡張）

現在Dexは無効化されていますが、将来SSO（GitHub、Google、OIDC）を有効化可能：

```yaml
# argocd.tf で dex.enabled = true に変更
dex = {
  enabled = true
}
```

## クリーンアップ

### Applicationの削除

```bash
# Application削除（Kubernetesリソースも削除）
argocd app delete <app-name>

# Application削除（Kubernetesリソースは残す）
argocd app delete <app-name> --cascade=false
```

### ArgoCD全体の削除

```bash
# Terraformで管理しているため
cd eks
terraform destroy -target=kubernetes_ingress_v1.argocd
terraform destroy -target=helm_release.argocd
terraform destroy -target=kubernetes_namespace.argocd
terraform destroy -target=aws_iam_role_policy_attachment.argocd
terraform destroy -target=aws_iam_role.argocd
terraform destroy -target=aws_iam_policy.argocd
```

## コスト

| リソース | 料金 | 備考 |
|---------|------|------|
| ALB | $0.0243/時間 | 約$0.58/日 |
| LCU（低トラフィック） | $0.008/LCU/時間 | 約$0.19/日 |
| **合計** | **約$0.77/日** | **約$23/月** |

**注意**:
- ArgoCD自体（Pod）は無料（既存のEKSノード内で実行）
- コストはALB（Ingress）のみ
- 学習後は必要に応じて削除を検討

## 次のステップ

### 1. 実践的なGitOpsワークフロー

- [ ] 既存のnginxをArgoCD管理に移行
- [ ] Gitでmanifestを変更してデプロイを体験
- [ ] ロールバック機能を試す

### 2. CI/CDパイプライン構築

- [ ] GitHub Actionsでイメージビルド
- [ ] ECRにイメージをプッシュ
- [ ] ArgoCDが新しいイメージを自動デプロイ

### 3. マルチ環境管理

- [ ] dev、staging、productionの環境を分離
- [ ] Kustomizeでオーバーレイ設定
- [ ] Applicationごとに異なる同期ポリシー

### 4. 高度な機能

- [ ] ApplicationSet（App of Apps パターン）
- [ ] Sync Wavesでデプロイ順序制御
- [ ] Notificationsで Slack 通知
- [ ] プロジェクト分離とRBAC

## 参考リンク

- [ArgoCD公式ドキュメント](https://argo-cd.readthedocs.io/)
- [ArgoCD GitHub](https://github.com/argoproj/argo-cd)
- [GitOps原則](https://opengitops.dev/)
- [Application CRD仕様](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/)
- [Best Practices](https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/)

## FAQ

### Q: 手動でkubectl applyしたリソースはどうなる？

A: ArgoCDは手動変更を検知し、`OutOfSync`として表示します。`selfHeal: true`の場合、自動的にGitの状態に戻されます。

### Q: 複数の環境（dev/staging/prod）を管理するには？

A: Kustomizeのオーバーレイ、またはHelmのvalues.yamlを環境ごとに用意し、別々のApplicationとして管理します。

### Q: Secretの管理は？

A: 以下の方法があります：
- Sealed Secrets（暗号化してGitにコミット）
- External Secrets Operator（AWS Secrets Managerと連携）
- Vault（HashiCorp Vault）

### Q: ArgoCDとFluxの違いは？

A: どちらもGitOpsツールですが、ArgoCDはWeb UIが充実しており初心者向け。FluxはCLI中心でよりシンプル。

### Q: 本番環境で使える？

A: はい。ただし、以下を検討してください：
- HTTPS/TLS（ACM証明書）の有効化
- Dex（SSO）の有効化
- マルチクラスタ管理
- バックアップとディザスタリカバリ
