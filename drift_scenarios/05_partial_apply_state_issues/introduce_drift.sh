#!/usr/bin/env bash
# Simulate partial apply by directly manipulating the Terraform state file
# to remove a resource that should exist (simulating failed creation)
# WARNING: This modifies the Terraform state file. Use only in test environments.
set -euo pipefail

SYSTEM_PATH="${SYSTEM_PATH:-infra/reference_systems/small_composable}"
NAME_PREFIX="${DRIFT_NAME_PREFIX:-iac-study-dev}"
AWS_REGION="${AWS_REGION:-us-east-1}"

echo "[drift] Simulating partial apply / state corruption..."
echo ""

# Method 1: Remove a resource from state (it still exists in AWS)
# This simulates the scenario where terraform applied a resource but failed to
# update the state file before the process was killed.
if command -v terraform &>/dev/null && [[ -d "$SYSTEM_PATH" ]]; then
  echo "[drift] Attempting to remove CloudWatch log group from state..."
  echo "[drift] (The resource still exists in AWS but Terraform won't know about it)"
  
  LOG_GROUP_RESOURCE=$(cd "$SYSTEM_PATH" && terraform state list 2>/dev/null | grep 'cloudwatch_log_group' | head -1 || true)
  
  if [[ -n "$LOG_GROUP_RESOURCE" ]]; then
    echo "[drift] Removing from state: $LOG_GROUP_RESOURCE"
    (cd "$SYSTEM_PATH" && terraform state rm "$LOG_GROUP_RESOURCE" 2>/dev/null) || true
    echo "[drift] State modified. Terraform will now try to CREATE the log group on next apply,"
    echo "[drift] but it already exists in AWS → potential conflict."
  else
    echo "[drift] No log group resource found in state"
  fi
else
  echo "[drift] Terraform not available or system path not found"
  echo "[drift] In a real test: interrupt apply with Ctrl+C during resource creation"
fi

# Method 2: Simulate with a real interruption using timeout
echo ""
echo "[drift] Alternative: Use 'timeout 5s terraform apply' to force interruption"
echo "[drift] This will create some resources and then kill the process"
echo "[drift] BE CAREFUL: Only use in throwaway test environments"
