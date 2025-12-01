# EKS完全クリーンアップ手順

## 概要

月額$200のコスト削減のため、EKS Cluster含む全リソースを削除します。
ECR Repository と S3 Bucket のみ保持（月額$1）。

**推定所要時間**: 30-45分

---

## 前提条件

- ✅ Terraform 1.0以上
- ✅ AWS CLI設定済み
- ✅ kubectl インストール済み
- ✅ GitHub Actions無効化確認

---

## ⚠️ 重要な注意事項

### Critical: ECR/S3の保護

`eks/ecr.tf` と `eks/s3.tf` は `force_destroy = true` が設定されているため、
**terraform destroy実行前に必ずTerraform State管理から除外する必要があります**。

除外しない場合、ECRイメージとS3データが完全削除されます。

---

## Step 1: Terraform State Backup

### 1.1 バックアップディレクトリ作成

```bash
cd /home/glkt/projects/terraform-eks-study

# バックアップディレクトリ作成
mkdir -p backup/terraform-state
```

### 1.2 State Files Backup

```bash
cd eks

# タイムスタンプ付きバックアップ
cp terraform.tfstate ../backup/terraform-state/terraform.tfstate.$(date +%Y%m%d_%H%M%S)
cp terraform.tfstate.backup ../backup/terraform-state/terraform.tfstate.backup.$(date +%Y%m%d_%H%M%S)

# State list保存
terraform state list > ../backup/terraform-state-list.txt

# 確認
ls -lh ../backup/terraform-state/
```

**期待される出力**:
```
terraform.tfstate.20251201_HHMMSS
terraform.tfstate.backup.20251201_HHMMSS
terraform-state-list.txt
```

---

## Step 2: 保持リソース情報取得

削除前に保持リソースの情報を記録します。

### 2.1 ECR Repository

```bash
# Repository URL
aws ecr describe-repositories \
  --repository-names eks-study-demo-app \
  --region ap-northeast-1 \
  --query 'repositories[0].repositoryUri' \
  --output text

# イメージ一覧
aws ecr list-images \
  --repository-name eks-study-demo-app \
  --region ap-northeast-1 \
  --query 'imageIds[*].imageTag' \
  --output table
```

### 2.2 S3 Bucket

```bash
# Bucket名
aws s3 ls | grep eks-study-irsa-test

# 内容確認
BUCKET=$(aws s3 ls | grep eks-study-irsa-test | awk '{print $3}')
aws s3 ls s3://$BUCKET/
```

---

## Step 3: ECR/S3をTerraform管理から除外

**🚨 最重要ステップ**: これを実行しないとECR/S3が削除されます

```bash
cd /home/glkt/projects/terraform-eks-study/eks

# ECR Repository除外
terraform state rm aws_ecr_repository.demo_app
terraform state rm aws_ecr_lifecycle_policy.demo_app

# S3 Bucket除外
terraform state rm aws_s3_bucket.irsa_test
terraform state rm aws_s3_bucket_versioning.irsa_test
terraform state rm aws_s3_bucket_public_access_block.irsa_test
terraform state rm aws_s3_object.test_file
terraform state rm random_id.bucket_suffix
```

**期待される出力**:
```
Removed aws_ecr_repository.demo_app
Removed aws_ecr_lifecycle_policy.demo_app
Removed aws_s3_bucket.irsa_test
...
```

### 3.1 除外確認

```bash
# ECR/S3が管理対象外になっていることを確認
terraform state list | grep -E "ecr|s3"
```

**期待される出力**: （何も表示されない = 正常）

---

## Step 4: Terraform Destroy Dry-run

### 4.1 削除対象確認

```bash
terraform plan -destroy
```

**確認ポイント**:
- ✅ ECR Repository が削除対象に **含まれていない**
- ✅ S3 Bucket が削除対象に **含まれていない**
- ✅ EKS Cluster が削除対象に **含まれている**
- ✅ VPC が削除対象に **含まれている**
- ✅ NAT Gateway が削除対象に **含まれている**

**削除されるリソース数**: 約50個

---

## Step 5: LoadBalancer事前削除（推奨）

ALB削除遅延を防ぐため、Ingressを先に削除します。

```bash
# kubectl設定確認
kubectl config current-context

# Ingress削除
kubectl delete ingress --all -A

# ALB削除確認（約2分待機）
sleep 120
aws elbv2 describe-load-balancers \
  --region ap-northeast-1 \
  --query 'LoadBalancers[*].[LoadBalancerName,State.Code]' \
  --output table
```

---

## Step 6: Terraform Destroy実行

### 6.1 最終バックアップ

```bash
cd /home/glkt/projects/terraform-eks-study/eks

cp terraform.tfstate ../backup/terraform-state/terraform.tfstate.before-destroy
```

### 6.2 削除実行

```bash
terraform destroy -auto-approve
```

**推定所要時間**: 15-30分

**進行状況**（別ターミナルで監視）:
```bash
watch -n 10 '
echo "=== EKS Cluster ==="
aws eks list-clusters --region ap-northeast-1

echo ""
echo "=== NAT Gateway ==="
aws ec2 describe-nat-gateways --region ap-northeast-1 --filter "Name=state,Values=available" --query "NatGateways[*].[NatGatewayId,State]" --output table

echo ""
echo "=== LoadBalancer ==="
aws elbv2 describe-load-balancers --region ap-northeast-1 --query "LoadBalancers[*].[LoadBalancerName,State.Code]" --output table
'
```

---

## Step 7: 削除確認

### 7.1 削除されたリソース確認

```bash
# EKS Cluster
aws eks list-clusters --region ap-northeast-1
# Expected: []

# EC2 Instances
aws ec2 describe-instances \
  --region ap-northeast-1 \
  --filters "Name=tag:Project,Values=eks-study" \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name]' \
  --output table
# Expected: (empty)

# NAT Gateway
aws ec2 describe-nat-gateways \
  --region ap-northeast-1 \
  --filter "Name=state,Values=available" \
  --query 'NatGateways[*].[NatGatewayId,State]' \
  --output table
# Expected: (empty)

# Elastic IP
aws ec2 describe-addresses \
  --region ap-northeast-1 \
  --query 'Addresses[*].[PublicIp,AllocationId]' \
  --output table
# Expected: (empty or 削除前と同じ数)

# LoadBalancer
aws elbv2 describe-load-balancers \
  --region ap-northeast-1 \
  --query 'LoadBalancers[*].[LoadBalancerName,State.Code]' \
  --output table
# Expected: (empty)

# VPC
aws ec2 describe-vpcs \
  --region ap-northeast-1 \
  --filters "Name=tag:Project,Values=eks-study" \
  --query 'Vpcs[*].[VpcId,CidrBlock]' \
  --output table
# Expected: (empty)

# CloudWatch Log Groups
aws logs describe-log-groups \
  --region ap-northeast-1 \
  --log-group-name-prefix /aws/eks/eks-study \
  --query 'logGroups[*].logGroupName' \
  --output table
# Expected: (empty)
```

### 7.2 保持リソース確認

```bash
# ECR Repository（保持されているべき）
aws ecr describe-repositories \
  --region ap-northeast-1 \
  --repository-names eks-study-demo-app
# Expected: Repository情報が表示される

# ECR イメージ
aws ecr list-images \
  --region ap-northeast-1 \
  --repository-name eks-study-demo-app
# Expected: イメージタグが表示される

# S3 Bucket（保持されているべき）
aws s3 ls | grep eks-study-irsa-test
# Expected: バケット名が表示される

# S3内容
BUCKET=$(aws s3 ls | grep eks-study-irsa-test | awk '{print $3}')
aws s3 ls s3://$BUCKET/
# Expected: test.txt が表示される
```

---

## Step 8: コスト確認

### 削減後の月額コスト

```bash
# ECR ストレージ使用量
aws ecr describe-images \
  --repository-name eks-study-demo-app \
  --region ap-northeast-1 \
  --query 'sum(imageDetails[*].imageSizeInBytes)' \
  --output text | awk '{print $1/1024/1024 " MB"}'

# S3 ストレージ使用量
aws s3 ls s3://$BUCKET --recursive --summarize | tail -2
```

**推定月額コスト**: 約$1/月
- ECR: ~$0.10/月（デモアプリ数百MBのみ）
- S3: ~$0.02/月（テストファイル数KBのみ）

**削減額**: $200 - $1 = **$199/月** (~$2,388/年)

---

## トラブルシューティング

### エラー1: Security Group削除失敗

**症状**:
```
Error: DependencyViolation: resource sg-xxxxx has a dependent object
```

**原因**: ENI（Network Interface）が残存

**対処**:
```bash
# VPC IDを確認
VPC_ID=$(aws ec2 describe-vpcs --region ap-northeast-1 --filters "Name=tag:Project,Values=eks-study" --query 'Vpcs[0].VpcId' --output text)

# ENI削除
aws ec2 describe-network-interfaces \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'NetworkInterfaces[*].NetworkInterfaceId' \
  --output text | \
  xargs -I {} aws ec2 delete-network-interface --network-interface-id {}

# 再実行
terraform destroy -auto-approve
```

---

### エラー2: LoadBalancer削除タイムアウト

**症状**:
```
Error: waiting for deletion: timeout while waiting for state
```

**原因**: ALB削除遅延

**対処**:
```bash
# ALB強制削除
aws elbv2 describe-load-balancers \
  --region ap-northeast-1 \
  --query 'LoadBalancers[*].LoadBalancerArn' \
  --output text | \
  xargs -I {} aws elbv2 delete-load-balancer --load-balancer-arn {}

# Target Group削除
aws elbv2 describe-target-groups \
  --region ap-northeast-1 \
  --query 'TargetGroups[*].TargetGroupArn' \
  --output text | \
  xargs -I {} aws elbv2 delete-target-group --target-group-arn {}

# 再実行
terraform destroy -auto-approve
```

---

### エラー3: NAT Gateway削除遅延

**症状**: NAT Gateway削除に10分以上かかる

**原因**: AWS側の処理遅延（正常動作）

**対処**: 待機するだけ（terraform destroyは自動で待機します）

---

### エラー4: State除外し忘れ

**症状**: ECR/S3が削除されてしまった

**対処**: 残念ながら復帰不可能です。以下で再構築：

```bash
# ECR Repository再作成
aws ecr create-repository --repository-name eks-study-demo-app --region ap-northeast-1

# S3 Bucket再作成
aws s3 mb s3://eks-study-irsa-test-$(openssl rand -hex 4) --region ap-northeast-1

# デモアプリイメージ再ビルド
cd /home/glkt/projects/terraform-eks-study/app
docker build -t eks-study-demo-app:latest .
# ... ECR push手順（割愛）
```

---

## 次のステップ

削除完了後、以下を確認してください：

1. ✅ 全AWSリソースが削除されている
2. ✅ ECR Repository が保持されている
3. ✅ S3 Bucket が保持されている
4. ✅ Terraform State が保存されている
5. ✅ 月額コストが$1程度に削減されている

復帰が必要になった場合は **`RESTORE.md`** を参照してください。
