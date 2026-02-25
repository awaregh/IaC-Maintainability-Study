#!/usr/bin/env bash
# Simulate data source nondeterminism by directly manipulating a referenced SSM parameter
# In practice, this simulates what happens when an AWS data source returns updated values.
set -euo pipefail

NAME_PREFIX="${DRIFT_NAME_PREFIX:-iac-study-dev}"
AWS_REGION="${AWS_REGION:-us-east-1}"

echo "[drift] Simulating data source nondeterminism..."
echo "[drift] In a real scenario, AWS releases a new AMI and the data source returns the new ID."
echo ""

# Simulate by creating a parameter that mimics a changed data source result
# (In layer-based/state-per-stack, data sources via SSM are common)
PARAM_NAME="/${NAME_PREFIX}/test/ami_id"
ORIGINAL_VALUE="ami-0abcdef1234567890"
DRIFTED_VALUE="ami-0fedcba9876543210"

echo "[drift] Writing 'original' AMI ID to SSM parameter: $PARAM_NAME"
aws ssm put-parameter \
  --region "$AWS_REGION" \
  --name "$PARAM_NAME" \
  --value "$ORIGINAL_VALUE" \
  --type String \
  --overwrite \
  --no-cli-pager 2>/dev/null || echo "[drift] SSM put failed (credentials may not be available)"

echo "[drift] Simulating time passing... AWS releases new AMI..."
sleep 2

echo "[drift] Updating SSM parameter to 'drifted' value (new AMI released)..."
aws ssm put-parameter \
  --region "$AWS_REGION" \
  --name "$PARAM_NAME" \
  --value "$DRIFTED_VALUE" \
  --type String \
  --overwrite \
  --no-cli-pager 2>/dev/null || true

echo ""
echo "[drift] Data source nondeterminism simulated."
echo "[drift] If a Terraform resource references this SSM parameter as a data source,"
echo "[drift] the next plan will show a change (even though no Terraform code changed)."
echo ""
echo "[drift] In production: watch for 'aws_ami' data source changes in terraform plans."
echo "[drift] Mitigation: pin AMI IDs explicitly rather than using most_recent=true"
