#!/usr/bin/env bash
# Detect IAM drift using AWS CloudTrail and terraform plan
set -euo pipefail

NAME_PREFIX="${DRIFT_NAME_PREFIX:-iac-study-dev}"
AWS_REGION="${AWS_REGION:-us-east-1}"
ROLE_NAME="${NAME_PREFIX}-ecs-task"

echo "[detect] Checking for IAM config drift..."

# Method 1: Check CloudTrail for recent IAM mutations
echo "[detect] Querying CloudTrail for IAM policy changes in last 1 hour..."
RECENT_IAM_EVENTS=$(aws cloudtrail lookup-events \
  --region "$AWS_REGION" \
  --lookup-attributes AttributeKey=EventName,AttributeValue=PutRolePolicy \
  --start-time "$(date -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -v-1H +%Y-%m-%dT%H:%M:%SZ)" \
  --query "Events[?contains(Resources[*].ResourceName, '${ROLE_NAME}')].{Time:EventTime,User:Username}" \
  --output text 2>/dev/null || echo "")

if [[ -n "$RECENT_IAM_EVENTS" ]]; then
  echo "[detect] IAM DRIFT DETECTED: Recent PutRolePolicy events found:"
  echo "$RECENT_IAM_EVENTS"
  IAM_DRIFT=true
else
  echo "[detect] No recent IAM changes found in CloudTrail"
  IAM_DRIFT=false
fi

# Method 2: Compare actual policy with expected (simplified check)
if aws iam get-role --role-name "$ROLE_NAME" --no-cli-pager 2>/dev/null; then
  ACTUAL_POLICY=$(aws iam get-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-name "${NAME_PREFIX}-ecs-task-permissions" \
    --query 'PolicyDocument' \
    --output json 2>/dev/null || echo "{}")

  # Check if wildcard Resource has crept in (security smell)
  if echo "$ACTUAL_POLICY" | grep -q '"Resource": "\*"'; then
    echo "[detect] SECURITY DRIFT DETECTED: IAM policy contains Resource: '*' (overly broad)"
    IAM_DRIFT=true
  fi

  # Check for unexpected actions (s3:ListAllMyBuckets is our indicator)
  if echo "$ACTUAL_POLICY" | grep -q 'ListAllMyBuckets'; then
    echo "[detect] DRIFT DETECTED: IAM policy contains unauthorized action ListAllMyBuckets"
    IAM_DRIFT=true
  fi
fi

if [[ "${IAM_DRIFT:-false}" == "true" ]]; then
  echo "[detect] Recommendation: Run 'terraform plan' to see full diff"
  echo "[detect] Run 'terraform apply' to remediate (revert to declared policy)"
  exit 2
else
  echo "[detect] No IAM drift detected"
  exit 0
fi
