#!/usr/bin/env bash
# Introduce IAM drift by modifying an ECS task role policy
# to add a broader S3 permission than Terraform declared
set -euo pipefail

NAME_PREFIX="${DRIFT_NAME_PREFIX:-iac-study-dev}"
AWS_REGION="${AWS_REGION:-us-east-1}"
ROLE_NAME="${NAME_PREFIX}-ecs-task"

echo "[drift] Introducing IAM config drift..."
echo "[drift] Role: $ROLE_NAME"

# Check if role exists
if ! aws iam get-role --role-name "$ROLE_NAME" --no-cli-pager 2>/dev/null; then
  echo "[drift] Role $ROLE_NAME not found - creating simulated drift in a test policy"
  
  # Show what the drift would look like without modifying real resources
  cat << 'POLICY'
[drift] Simulated policy change (would add broader permissions):
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "BroadS3Access",
      "Effect": "Allow",
      "Action": "s3:*",
      "Resource": "*"
    }
  ]
}
POLICY
  exit 0
fi

# Store original policy
ORIGINAL_POLICY=$(aws iam get-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name "${NAME_PREFIX}-ecs-task-permissions" \
  --query 'PolicyDocument' \
  --output json 2>/dev/null || echo "{}")

echo "$ORIGINAL_POLICY" > /tmp/original_iac_policy_backup.json
echo "[drift] Original policy backed up to /tmp/original_iac_policy_backup.json"

# Create drifted policy: broader S3 permissions (security downgrade)
DRIFTED_POLICY=$(cat << 'POLICY'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "BroadenedS3Access",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:ListAllMyBuckets",
        "s3:GetBucketLocation",
        "s3:GetBucketPolicy"
      ],
      "Resource": "*"
    },
    {
      "Sid": "CloudWatchLogs",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:CreateLogGroup"
      ],
      "Resource": "*"
    }
  ]
}
POLICY
)

echo "[drift] Applying broadened IAM policy (simulating unauthorized access expansion)..."
aws iam put-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name "${NAME_PREFIX}-ecs-task-permissions" \
  --policy-document "$DRIFTED_POLICY" \
  --no-cli-pager

echo "[drift] IAM policy broadened. Terraform will detect and revert this on next apply."
echo "[drift] To restore manually: aws iam put-role-policy --role-name $ROLE_NAME ..."
