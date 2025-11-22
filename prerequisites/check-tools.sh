#!/bin/bash

# =============================================================================
# Terraform + EKS 学習環境 ツール確認スクリプト
# =============================================================================

set -e

echo "=========================================="
echo "  環境チェックスクリプト"
echo "=========================================="
echo ""

# 色の定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

check_command() {
    local cmd=$1
    local name=$2
    local install_hint=$3

    if command -v "$cmd" &> /dev/null; then
        version=$($cmd --version 2>&1 | head -n 1)
        echo -e "${GREEN}[OK]${NC} $name: $version"
        return 0
    else
        echo -e "${RED}[NG]${NC} $name がインストールされていません"
        echo "    インストール: $install_hint"
        return 1
    fi
}

echo "--- 必須ツール ---"
echo ""

errors=0

# AWS CLI
check_command "aws" "AWS CLI" "https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html" || ((errors++))

# Terraform
check_command "terraform" "Terraform" "https://developer.hashicorp.com/terraform/downloads" || ((errors++))

# kubectl
check_command "kubectl" "kubectl" "https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/" || ((errors++))

echo ""
echo "--- オプションツール ---"
echo ""

# eksctl
check_command "eksctl" "eksctl" "https://eksctl.io/installation/" || true

# Docker
check_command "docker" "Docker" "Docker Desktop または docker.io" || true

# jq (JSONパース用)
check_command "jq" "jq" "sudo apt install jq" || true

echo ""
echo "--- AWS認証情報チェック ---"
echo ""

if aws sts get-caller-identity &> /dev/null; then
    identity=$(aws sts get-caller-identity --output json)
    account=$(echo "$identity" | jq -r '.Account // "取得失敗"')
    arn=$(echo "$identity" | jq -r '.Arn // "取得失敗"')
    echo -e "${GREEN}[OK]${NC} AWS認証済み"
    echo "    Account: $account"
    echo "    ARN: $arn"
else
    echo -e "${RED}[NG]${NC} AWS認証情報が設定されていません"
    echo "    実行: aws configure"
    ((errors++))
fi

echo ""
echo "--- 環境変数チェック ---"
echo ""

if [ -n "$AWS_PROFILE" ]; then
    echo -e "${GREEN}[INFO]${NC} AWS_PROFILE: $AWS_PROFILE"
else
    echo -e "${YELLOW}[INFO]${NC} AWS_PROFILE: 未設定 (default使用)"
fi

if [ -n "$AWS_REGION" ]; then
    echo -e "${GREEN}[INFO]${NC} AWS_REGION: $AWS_REGION"
else
    region=$(aws configure get region 2>/dev/null || echo "未設定")
    echo -e "${YELLOW}[INFO]${NC} AWS_REGION: 環境変数未設定 (config: $region)"
fi

echo ""
echo "=========================================="

if [ $errors -gt 0 ]; then
    echo -e "${RED}エラーが $errors 件あります。修正してください。${NC}"
    exit 1
else
    echo -e "${GREEN}すべてのチェックが完了しました！${NC}"
    exit 0
fi
