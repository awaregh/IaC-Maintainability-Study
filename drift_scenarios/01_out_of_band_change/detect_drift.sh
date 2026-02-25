#!/usr/bin/env bash
# Detect drift in the ECS service desired count
set -euo pipefail

NAME_PREFIX="${DRIFT_NAME_PREFIX:-iac-study-dev}"
AWS_REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="${NAME_PREFIX}-cluster"
SERVICE_NAME="${NAME_PREFIX}-app"

echo "[detect] Checking ECS service for drift..."

# Get actual desired count from AWS
ACTUAL_COUNT=$(aws ecs describe-services \
  --region "$AWS_REGION" \
  --cluster "$CLUSTER_NAME" \
  --services "$SERVICE_NAME" \
  --query 'services[0].desiredCount' \
  --output text 2>/dev/null || echo "unknown")

echo "[detect] Actual ECS desired count: $ACTUAL_COUNT"
echo "[detect] Expected (Terraform): 2"

if [[ "$ACTUAL_COUNT" != "2" && "$ACTUAL_COUNT" != "unknown" ]]; then
  echo "[detect] DRIFT DETECTED: ECS desired count is $ACTUAL_COUNT, expected 2"
  echo "[detect] Run 'terraform plan' to confirm and 'terraform apply' to remediate"
  exit 2
else
  echo "[detect] No ECS count drift detected"
  exit 0
fi
