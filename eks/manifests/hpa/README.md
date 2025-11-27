# Horizontal Pod Autoscaler (HPA)

## 概要

Horizontal Pod Autoscaler (HPA) は、CPU使用率やメモリ使用量などのメトリクスに基づいて、Podの数を自動的にスケーリングする機能です。

## 学習目標

- HPAの動作原理を理解する
- Metrics Serverの役割を学ぶ
- CPU使用率に基づく自動スケーリングを実装する
- 負荷テストによるスケーリング動作を確認する

## 前提条件

1. **EKSクラスターが稼働中**
   ```bash
   kubectl get nodes
   ```

2. **Metrics Serverが動作中**（EKSではデフォルトで有効）
   ```bash
   kubectl get deployment metrics-server -n kube-system
   ```

3. **nginx-deploymentが存在**
   ```bash
   kubectl get deployment nginx-deployment
   ```

## デプロイ手順

### 1. HPAを適用

```bash
kubectl apply -f hpa.yaml
```

### 2. HPA の状態を確認

```bash
kubectl get hpa
```

初期状態では、現在のCPU使用率が表示されます：

```
NAME        REFERENCE                     TARGETS   MINPODS   MAXPODS   REPLICAS
nginx-hpa   Deployment/nginx-deployment   0%/50%    1         5         1
```

### 3. 詳細情報を確認

```bash
kubectl describe hpa nginx-hpa
```

## 負荷テストとスケーリング確認

### 1. 負荷生成Podを起動

```bash
kubectl apply -f load-generator.yaml
```

このPodは無限ループでnginxサービスにHTTPリクエストを送信し、CPU負荷を発生させます。

### 2. スケーリングをリアルタイムで監視

別のターミナルで以下のコマンドを実行：

```bash
# HPAの状態を監視
kubectl get hpa nginx-hpa --watch

# または、Podの数を監視
kubectl get pods -l app=nginx --watch
```

### 3. 期待される動作

1. **負荷発生後（30秒〜1分）**: CPU使用率が50%を超える
   ```
   NAME        REFERENCE                     TARGETS    MINPODS   MAXPODS   REPLICAS
   nginx-hpa   Deployment/nginx-deployment   85%/50%    1         5         1
   ```

2. **スケールアップ（1〜2分後）**: Podが増加
   ```
   nginx-hpa   Deployment/nginx-deployment   65%/50%    1         5         3
   ```

3. **最大5 Podまでスケール**

### 4. スケールダウンの確認

負荷生成を停止してスケールダウンを確認：

```bash
kubectl delete pod load-generator
```

約5分後（stabilizationWindow）、CPU使用率が低下し、Podが徐々に削減されます。

## トラブルシューティング

### HPAが "unknown" と表示される

```
NAME        REFERENCE                     TARGETS         MINPODS   MAXPODS   REPLICAS
nginx-hpa   Deployment/nginx-deployment   <unknown>/50%   1         5         0
```

**原因**: Metrics Serverが動作していないか、Deploymentにresource requestsが設定されていない

**解決策**:
```bash
# Metrics Serverを確認
kubectl get deployment metrics-server -n kube-system

# Deploymentのresource requestsを確認
kubectl get deployment nginx-deployment -o yaml | grep -A 5 resources
```

### Podがスケールしない

**確認事項**:
1. CPU使用率が50%を超えているか
   ```bash
   kubectl top pods -l app=nginx
   ```

2. HPAのイベントを確認
   ```bash
   kubectl describe hpa nginx-hpa
   ```

3. 負荷生成Podが実行中か
   ```bash
   kubectl get pod load-generator
   kubectl logs load-generator
   ```

### スケールダウンが遅い

**説明**: 意図的な設計です。
- `stabilizationWindowSeconds: 300` により、5分間待機してからスケールダウンします
- 頻繁なスケーリングによる不安定性を防ぐためです

## HPAの設定値解説

| パラメータ | 値 | 説明 |
|-----------|-----|------|
| minReplicas | 1 | 最小Pod数 |
| maxReplicas | 5 | 最大Pod数 |
| targetCPUUtilizationPercentage | 50% | 目標CPU使用率 |
| scaleDown.stabilizationWindow | 300秒 | スケールダウン前の待機時間 |
| scaleUp.stabilizationWindow | 0秒 | スケールアップは即座に実行 |

## クリーンアップ

```bash
# 負荷生成Podを削除（まだ残っている場合）
kubectl delete -f load-generator.yaml

# HPAを削除
kubectl delete -f hpa.yaml
```

**注意**: nginx-deploymentは削除しません（他の機能でも使用するため）。

## 本番環境での推奨設定

```yaml
spec:
  minReplicas: 2  # 可用性のため最低2
  maxReplicas: 10  # トラフィックに応じて調整
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70  # より高い閾値
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

## 次のステップ

- **メモリベースのスケーリング**: CPU以外のメトリクスを追加
- **カスタムメトリクス**: Prometheusメトリクスに基づくスケーリング
- **Cluster Autoscaler**: ノード数も自動スケーリング

## 参考リンク

- [Kubernetes HPA公式ドキュメント](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
- [AWS EKS HPA](https://docs.aws.amazon.com/eks/latest/userguide/horizontal-pod-autoscaler.html)
