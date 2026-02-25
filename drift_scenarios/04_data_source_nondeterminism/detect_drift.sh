#!/usr/bin/env bash
# Detect data source nondeterminism by comparing plan output from two runs
set -euo pipefail

NAME_PREFIX="${DRIFT_NAME_PREFIX:-iac-study-dev}"
AWS_REGION="${AWS_REGION:-us-east-1}"
SYSTEM_PATH="${SYSTEM_PATH:-.}"

echo "[detect] Checking for data source nondeterminism..."
echo "[detect] Running two consecutive terraform plans and comparing resource change counts..."

PLAN1_CHANGES=0
PLAN2_CHANGES=0

if command -v terraform &>/dev/null && [[ -d "$SYSTEM_PATH" ]]; then
  (cd "$SYSTEM_PATH" && terraform plan -detailed-exitcode -no-color 2>/dev/null) && PLAN1_CHANGES=0 || PLAN1_CHANGES=1
  sleep 30  # Allow time for any eventual-consistency effects
  (cd "$SYSTEM_PATH" && terraform plan -detailed-exitcode -no-color 2>/dev/null) && PLAN2_CHANGES=0 || PLAN2_CHANGES=1

  if [[ "$PLAN1_CHANGES" -eq 0 && "$PLAN2_CHANGES" -ne 0 ]]; then
    echo "[detect] NONDETERMINISM DETECTED: plan 1 showed no changes, plan 2 showed changes"
    exit 2
  fi
fi

echo "[detect] SSM parameter check for AMI drift simulation..."
PARAM_VALUE=$(aws ssm get-parameter \
  --region "$AWS_REGION" \
  --name "/${NAME_PREFIX}/test/ami_id" \
  --query 'Parameter.Value' \
  --output text 2>/dev/null || echo "not_found")

if [[ "$PARAM_VALUE" == "ami-0fedcba9876543210" ]]; then
  echo "[detect] DRIFT DETECTED: SSM parameter shows drifted AMI ID: $PARAM_VALUE"
  exit 2
else
  echo "[detect] No data source nondeterminism detected"
  exit 0
fi
