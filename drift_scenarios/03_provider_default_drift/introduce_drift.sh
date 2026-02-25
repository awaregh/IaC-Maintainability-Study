#!/usr/bin/env bash
# Introduce provider default drift by modifying an S3 bucket's ownership setting
# to a non-Terraform-managed state that conflicts with provider defaults
set -euo pipefail

NAME_PREFIX="${DRIFT_NAME_PREFIX:-iac-study-dev}"
AWS_REGION="${AWS_REGION:-us-east-1}"

# Find the S3 bucket
BUCKET_NAME=$(aws s3api list-buckets \
  --query "Buckets[?starts_with(Name, '${NAME_PREFIX}-artifacts')].Name | [0]" \
  --output text 2>/dev/null || echo "")

if [[ -z "$BUCKET_NAME" || "$BUCKET_NAME" == "None" ]]; then
  echo "[drift] No bucket found with prefix ${NAME_PREFIX}-artifacts"
  echo "[drift] Simulating drift by removing bucket notification configuration"
  exit 0
fi

echo "[drift] Found bucket: $BUCKET_NAME"
echo "[drift] Modifying bucket object ownership to introduce provider default drift..."

# Change object ownership - this can conflict with Terraform's desired state
aws s3api put-bucket-ownership-controls \
  --region "$AWS_REGION" \
  --bucket "$BUCKET_NAME" \
  --ownership-controls 'Rules=[{ObjectOwnership=BucketOwnerPreferred}]' \
  --no-cli-pager 2>/dev/null || echo "[drift] Could not set ownership controls (may require ACLs enabled)"

# Add a bucket notification configuration that Terraform doesn't manage
# This simulates AWS-side changes that create provider default mismatches
aws s3api put-bucket-tagging \
  --region "$AWS_REGION" \
  --bucket "$BUCKET_NAME" \
  --tagging 'TagSet=[{Key=DriftTest,Value=provider-default-drift},{Key=ManagedBy,Value=manual}]' \
  --no-cli-pager

echo "[drift] Bucket $BUCKET_NAME modified. Provider default drift introduced."
echo "[drift] Terraform plan will now show tag drift (ManagedBy tag conflict)"
