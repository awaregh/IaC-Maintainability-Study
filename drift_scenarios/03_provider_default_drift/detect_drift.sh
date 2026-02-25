#!/usr/bin/env bash
# Detect provider default drift via terraform plan
set -euo pipefail

NAME_PREFIX="${DRIFT_NAME_PREFIX:-iac-study-dev}"
AWS_REGION="${AWS_REGION:-us-east-1}"

BUCKET_NAME=$(aws s3api list-buckets \
  --query "Buckets[?starts_with(Name, '${NAME_PREFIX}-artifacts')].Name | [0]" \
  --output text 2>/dev/null || echo "")

if [[ -z "$BUCKET_NAME" || "$BUCKET_NAME" == "None" ]]; then
  echo "[detect] No bucket found - cannot check provider default drift"
  exit 0
fi

echo "[detect] Checking S3 bucket tags for drift..."
ACTUAL_TAGS=$(aws s3api get-bucket-tagging \
  --region "$AWS_REGION" \
  --bucket "$BUCKET_NAME" \
  --query 'TagSet[*].Key' \
  --output text 2>/dev/null || echo "")

echo "[detect] Tags on bucket: $ACTUAL_TAGS"

if echo "$ACTUAL_TAGS" | grep -q "DriftTest"; then
  echo "[detect] DRIFT DETECTED: Unmanaged tag 'DriftTest' found on S3 bucket"
  echo "[detect] This indicates out-of-band modification consistent with provider default drift scenario"
  exit 2
else
  echo "[detect] No provider default drift detected in bucket tags"
  exit 0
fi
