#!/usr/bin/env bash
# Detect partial apply drift by comparing state with actual AWS resources
set -euo pipefail

NAME_PREFIX="${DRIFT_NAME_PREFIX:-iac-study-dev}"
AWS_REGION="${AWS_REGION:-us-east-1}"
SYSTEM_PATH="${SYSTEM_PATH:-infra/reference_systems/small_composable}"

echo "[detect] Checking for partial apply / state issues..."

DRIFT_FOUND=false

# Check 1: Does the ECS cluster in state match what's in AWS?
if command -v terraform &>/dev/null && [[ -d "$SYSTEM_PATH" ]]; then
  STATE_CLUSTERS=$(cd "$SYSTEM_PATH" && terraform state list 2>/dev/null | grep 'aws_ecs_cluster' | wc -l || echo 0)
  
  ACTUAL_CLUSTERS=$(aws ecs list-clusters \
    --region "$AWS_REGION" \
    --query "clusterArns[?contains(@, '${NAME_PREFIX}')]" \
    --output text 2>/dev/null | wc -w || echo 0)

  echo "[detect] ECS clusters in state:  $STATE_CLUSTERS"
  echo "[detect] ECS clusters in AWS:    $ACTUAL_CLUSTERS"

  if [[ "$STATE_CLUSTERS" -ne "$ACTUAL_CLUSTERS" ]]; then
    echo "[detect] PARTIAL APPLY DRIFT DETECTED: state/AWS cluster count mismatch"
    DRIFT_FOUND=true
  fi
fi

# Check 2: Verify CloudWatch log groups
CW_LOG_GROUPS_AWS=$(aws logs describe-log-groups \
  --region "$AWS_REGION" \
  --log-group-name-prefix "/ecs/${NAME_PREFIX}" \
  --query 'length(logGroups)' \
  --output text 2>/dev/null || echo 0)

echo "[detect] CloudWatch log groups in AWS matching prefix: $CW_LOG_GROUPS_AWS"

if [[ "$DRIFT_FOUND" == "true" ]]; then
  echo "[detect] Recommendation: Run 'terraform plan' and review output carefully"
  echo "[detect] Consider 'terraform import' to re-add orphaned resources to state"
  exit 2
else
  echo "[detect] No partial apply drift detected"
  exit 0
fi
