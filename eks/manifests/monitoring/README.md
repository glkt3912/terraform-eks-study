# Prometheus + Grafana 監視

## 概要

Prometheus と Grafana を使用したKubernetesクラスターの監視システムです。kube-prometheus-stackを使用して、メトリクス収集、可視化、アラートを実装します。

## 学習目標

- Prometheusのメトリクス収集の仕組みを理解する
- Grafanaでのダッシュボード作成を学ぶ
- Kubernetes固有のメトリクスを把握する
- アラート設定の基礎を習得する

## アーキテクチャ

```
┌──────────────────────────────────────────────────────────────┐
│ Grafana (可視化)                                             │
│ - ダッシュボード表示                                         │
│ - アラート通知                                               │
└────────────────────────┬─────────────────────────────────────┘
                         │ PromQL Query
                         ↓
┌──────────────────────────────────────────────────────────────┐
│ Prometheus (メトリクス収集・保存)                            │
│ - 時系列データベース                                         │
│ - スクレイピング                                             │
└────────────────────────┬─────────────────────────────────────┘
                         │ Scrape
                         ↓
┌─────────────┬──────────────────┬──────────────────┐
│             │                  │                  │
▼             ▼                  ▼                  ▼
┌─────────┐  ┌──────────┐  ┌────────────┐  ┌──────────┐
│ Node    │  │ Kube     │  │ cAdvisor   │  │ Custom   │
│ Exporter│  │ State    │  │ (Container │  │ App      │
│         │  │ Metrics  │  │ Metrics)   │  │ Metrics  │
└─────────┘  └──────────┘  └────────────┘  └──────────┘
```

### コンポーネント

| コンポーネント | 役割 |
|--------------|------|
| **Prometheus** | メトリクスの収集・保存・クエリ |
| **Grafana** | メトリクスの可視化・ダッシュボード |
| **Alertmanager** | アラートのルーティング・通知 |
| **Node Exporter** | ノード（サーバー）レベルのメトリクス |
| **Kube State Metrics** | Kubernetesオブジェクトの状態メトリクス |
| **cAdvisor** | コンテナレベルのメトリクス（kubeletに組み込み済み） |

## 前提条件

### 1. Helmのインストール

```bash
# Helmがインストールされているか確認
helm version

# インストールされていない場合
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### 2. リソース確認

最小要件：
- CPU: 2コア以上
- メモリ: 4GB以上
- ストレージ: 10GB以上（永続化する場合）

```bash
# ノードのリソースを確認
kubectl top nodes
```

## インストール手順

### 1. Helm リポジトリを追加

```bash
# Prometheus Communityリポジトリを追加
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts

# リポジトリを更新
helm repo update
```

### 2. Namespaceを作成

```bash
kubectl create namespace monitoring
```

### 3. kube-prometheus-stackをインストール

```bash
# カスタム設定でインストール
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  -f eks/manifests/monitoring/prometheus-values.yaml

# インストール確認
helm list -n monitoring
```

### 4. Podの起動を確認

```bash
# すべてのPodが起動するまで待つ（2-3分）
kubectl get pods -n monitoring --watch

# 期待される出力（すべてRunning）
NAME                                                     READY   STATUS
alertmanager-prometheus-kube-prometheus-alertmanager-0   2/2     Running
prometheus-grafana-xxxxxxxxxx-xxxxx                      3/3     Running
prometheus-kube-prometheus-operator-xxxxxxxxxx-xxxxx     1/1     Running
prometheus-kube-state-metrics-xxxxxxxxxx-xxxxx           1/1     Running
prometheus-prometheus-kube-prometheus-prometheus-0       2/2     Running
prometheus-prometheus-node-exporter-xxxxx                1/1     Running
```

## Grafanaへのアクセス

### 方法1: LoadBalancer経由（推奨）

```bash
# Grafana ServiceのExternal IPを取得
export GRAFANA_LB=$(kubectl get svc -n monitoring prometheus-grafana -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

echo "Grafana URL: http://$GRAFANA_LB"

# ブラウザでアクセス
# デフォルトログイン情報:
# Username: admin
# Password: admin (prometheus-values.yamlで設定)
```

### 方法2: Port Forward（開発環境）

```bash
# Port forwardを開始
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

# ブラウザで http://localhost:3000 にアクセス
```

## Prometheusへのアクセス

```bash
# Port forward
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090

# ブラウザで http://localhost:9090 にアクセス
```

## 主要なダッシュボード

Grafanaにログイン後、左メニュー → Dashboards から以下の事前設定ダッシュボードを確認：

### 1. Kubernetes / Compute Resources / Cluster
- クラスター全体のCPU・メモリ使用率
- ノードごとのリソース使用状況

### 2. Kubernetes / Compute Resources / Namespace (Pods)
- Namespace別のリソース使用率
- Pod別のCPU・メモリ使用量

### 3. Kubernetes / Compute Resources / Node (Pods)
- ノード別のPodリソース使用状況

### 4. Kubernetes / Networking / Cluster
- ネットワークトラフィック
- パケット送受信量

### 5. Node Exporter / Nodes
- ノードのシステムメトリクス
- ディスク、CPU、メモリ、ネットワーク

## 有用なPromQLクエリ

Prometheus UI (http://localhost:9090) で以下のクエリを実行：

### CPU使用率

```promql
# クラスター全体のCPU使用率
sum(rate(container_cpu_usage_seconds_total[5m])) by (namespace)

# Pod別のCPU使用率
sum(rate(container_cpu_usage_seconds_total{pod!=""}[5m])) by (pod)

# ノード別のCPU使用率
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
```

### メモリ使用量

```promql
# Pod別のメモリ使用量（MB）
sum(container_memory_working_set_bytes{pod!=""}) by (pod) / 1024 / 1024

# Namespace別のメモリ使用量
sum(container_memory_working_set_bytes) by (namespace) / 1024 / 1024 / 1024

# ノードのメモリ使用率（%）
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100
```

### Pod状態

```promql
# Running状態のPod数
count(kube_pod_status_phase{phase="Running"})

# Pending状態のPod数
count(kube_pod_status_phase{phase="Pending"})

# Failed状態のPod数
count(kube_pod_status_phase{phase="Failed"})
```

### ネットワーク

```promql
# Pod別のネットワーク受信バイト/秒
sum(rate(container_network_receive_bytes_total[5m])) by (pod)

# Pod別のネットワーク送信バイト/秒
sum(rate(container_network_transmit_bytes_total[5m])) by (pod)
```

### ディスク

```promql
# ノードのディスク使用率（%）
(node_filesystem_size_bytes - node_filesystem_avail_bytes) / node_filesystem_size_bytes * 100

# ディスクI/O
rate(node_disk_read_bytes_total[5m])
rate(node_disk_written_bytes_total[5m])
```

## カスタムメトリクスの追加

### アプリケーションメトリクスの公開

アプリケーションで `/metrics` エンドポイントを公開：

```python
# Python Flask example
from prometheus_client import Counter, generate_latest

request_count = Counter('app_requests_total', 'Total requests')

@app.route('/metrics')
def metrics():
    return generate_latest()

@app.route('/')
def index():
    request_count.inc()
    return "Hello World"
```

### ServiceMonitorの作成

Prometheusに自動的にスクレイプさせる：

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: my-app-monitor
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: my-app
  endpoints:
  - port: metrics
    interval: 30s
```

または、Serviceにアノテーションを追加：

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"
    prometheus.io/path: "/metrics"
spec:
  selector:
    app: my-app
  ports:
  - port: 8080
    name: metrics
```

## アラートの設定

### PrometheusRuleの作成

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: custom-alerts
  namespace: monitoring
spec:
  groups:
  - name: custom
    interval: 30s
    rules:
    # CPU使用率が80%を超えた場合
    - alert: HighCPUUsage
      expr: |
        100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "High CPU usage on {{ $labels.instance }}"
        description: "CPU usage is {{ $value }}%"

    # メモリ使用率が90%を超えた場合
    - alert: HighMemoryUsage
      expr: |
        (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 90
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: "High memory usage on {{ $labels.instance }}"
        description: "Memory usage is {{ $value }}%"

    # Podが再起動を繰り返している場合
    - alert: PodCrashLooping
      expr: |
        rate(kube_pod_container_status_restarts_total[15m]) > 0
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "Pod {{ $labels.pod }} is crash looping"
        description: "Pod has restarted {{ $value }} times"
```

適用：
```bash
kubectl apply -f custom-alerts.yaml
```

## トラブルシューティング

### Podが起動しない

```bash
# Podの状態を確認
kubectl describe pod -n monitoring <pod-name>

# ログを確認
kubectl logs -n monitoring <pod-name>

# よくある原因:
# - リソース不足（CPU/メモリ）
# - Persistent Volumeの作成失敗
# - イメージのPull失敗
```

### Grafanaにアクセスできない

```bash
# Serviceを確認
kubectl get svc -n monitoring prometheus-grafana

# LoadBalancerが作成されているか確認
kubectl describe svc -n monitoring prometheus-grafana

# Port forwardで直接アクセスを試す
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
```

### メトリクスが表示されない

```bash
# Prometheusのターゲットを確認
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090

# ブラウザで http://localhost:9090/targets にアクセス
# すべてのターゲットが "UP" になっているか確認
```

### ディスク容量不足

```bash
# Prometheusのストレージ使用量を確認
kubectl exec -n monitoring prometheus-prometheus-kube-prometheus-prometheus-0 -c prometheus -- \
  du -sh /prometheus

# Retentionを短くする（helm upgrade）
helm upgrade prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  -f prometheus-values.yaml \
  --set prometheus.prometheusSpec.retention=3d
```

## クリーンアップ

```bash
# Helm releaseを削除
helm uninstall prometheus -n monitoring

# Namespaceを削除（すべてのリソースが削除されます）
kubectl delete namespace monitoring

# CRDs を削除（オプション）
kubectl delete crd prometheuses.monitoring.coreos.com
kubectl delete crd prometheusrules.monitoring.coreos.com
kubectl delete crd servicemonitors.monitoring.coreos.com
kubectl delete crd podmonitors.monitoring.coreos.com
kubectl delete crd alertmanagers.monitoring.coreos.com
kubectl delete crd alertmanagerconfigs.monitoring.coreos.com
```

## コスト

| リソース | 料金 | 備考 |
|---------|------|------|
| Grafana LoadBalancer | $0.0225/時間 | 約$0.54/日 |
| Prometheus（ストレージ） | EBS料金 | 永続化する場合のみ |
| リソース使用（CPU/メモリ） | ノード料金に含まれる | 追加ノード不要なら0円 |

**推定**: 約$0.54〜$1.00/日（LoadBalancer使用時）

## 本番環境での推奨設定

### 1. 永続ストレージの有効化

```yaml
prometheus:
  prometheusSpec:
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 50Gi

grafana:
  persistence:
    enabled: true
    size: 10Gi
```

### 2. リソース制限の調整

```yaml
prometheus:
  prometheusSpec:
    resources:
      requests:
        cpu: 1000m
        memory: 2Gi
      limits:
        cpu: 2000m
        memory: 4Gi
```

### 3. 高可用性設定

```yaml
prometheus:
  prometheusSpec:
    replicas: 2  # 冗長化

grafana:
  replicas: 2
```

### 4. アラート通知の設定

Slackやメールへの通知：

```yaml
alertmanager:
  config:
    global:
      slack_api_url: 'https://hooks.slack.com/services/xxx'
    route:
      receiver: 'slack'
    receivers:
    - name: 'slack'
      slack_configs:
      - channel: '#alerts'
        text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
```

## 次のステップ

- **カスタムダッシュボード作成**: ビジネスメトリクスの可視化
- **Loki統合**: ログ集約と分析
- **Jaeger統合**: 分散トレーシング
- **Thanos**: 長期ストレージとクエリ

## 参考リンク

- [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- [Prometheus公式ドキュメント](https://prometheus.io/docs/)
- [Grafana公式ドキュメント](https://grafana.com/docs/)
- [PromQL入門](https://prometheus.io/docs/prometheus/latest/querying/basics/)
