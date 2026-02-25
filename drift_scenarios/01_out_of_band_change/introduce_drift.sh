#!/usr/bin/env bash
# Introduce out-of-band drift by manually scaling the ECS service down
# Environment variables expected:
#   DRIFT_NAME_PREFIX - e.g. "iac-study-dev"
#   AWS_REGION        - e.g. "us-east-1" (default)

set -euo pipefail

NAME_PREFIX="${DRIFT_NAME_PREFIX:-iac-study-dev}"
AWS_REGION="${AWS_REGION:-us-east-1}"
CLUSTER_NAME="${NAME_PREFIX}-cluster"
SERVICE_NAME="${NAME_PREFIX}-app"
NEW_DESIRED_COUNT="${DRIFT_DESIRED_COUNT:-1}"

echo "[drift] Introducing out-of-band ECS scaling change..."
echo "[drift] Cluster:  $CLUSTER_NAME"
echo "[drift] Service:  $SERVICE_NAME"
echo "[drift] New count: $NEW_DESIRED_COUNT"

# Scale ECS service manually (outside of Terraform)
aws ecs update-service \
  --region "$AWS_REGION" \
  --cluster "$CLUSTER_NAME" \
  --service "$SERVICE_NAME" \
  --desired-count "$NEW_DESIRED_COUNT" \
  --no-cli-pager

echo "[drift] ECS service updated. Waiting 15s for stabilization..."
sleep 15

# Also demonstrate tag drift - add an unmanaged tag
CLUSTER_ARN=$(aws ecs describe-clusters \
  --region "$AWS_REGION" \
  --clusters "$CLUSTER_NAME" \
  --query 'clusters[0].clusterArn' \
  --output text 2>/dev/null || true)

if [[ -n "$CLUSTER_ARN" && "$CLUSTER_ARN" != "None" ]]; then
  aws ecs tag-resource \
    --region "$AWS_REGION" \
    --resource-arn "$CLUSTER_ARN" \
    --tags key=ManuallyAdded,value=drift-test-tag \
    --no-cli-pager 2>/dev/null || true
  echo "[drift] Added out-of-band tag to ECS cluster"
fi

echo "[drift] Drift introduction complete."
