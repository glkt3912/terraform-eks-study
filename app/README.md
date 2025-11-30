# CI/CD Demo Application

シンプルな Go 製 Web アプリケーション。CI/CD パイプラインのデモ用。

## 機能

- バージョン情報の表示
- Git コミット SHA の表示
- ビルド時刻の表示
- ヘルスチェックエンドポイント

## エンドポイント

- `GET /` - Web UI（バージョン情報を表示）
- `GET /health` - ヘルスチェック
- `GET /version` - バージョン情報（JSON）

## ローカル実行

```bash
go run main.go
```

ブラウザで http://localhost:8080 を開く

## Docker ビルド

```bash
docker build \
  --build-arg VERSION=1.0.0 \
  --build-arg GIT_COMMIT=$(git rev-parse HEAD) \
  --build-arg BUILD_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ") \
  -t demo-app:latest .
```

## Docker 実行

```bash
docker run -p 8080:8080 demo-app:latest
```
