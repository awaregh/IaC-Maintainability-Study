#!/usr/bin/env bash
# Introduce version drift by modifying the provider constraint in versions.tf
# WARNING: This modifies the versions.tf file in the target system.
# Run in a separate branch or restore file afterward.
set -euo pipefail

SYSTEM_PATH="${SYSTEM_PATH:-infra/reference_systems/monolithic}"
VERSIONS_FILE="$SYSTEM_PATH/versions.tf"

if [[ ! -f "$VERSIONS_FILE" ]]; then
  echo "[drift] versions.tf not found at $VERSIONS_FILE"
  exit 1
fi

echo "[drift] Current provider constraint:"
grep 'version.*aws' "$VERSIONS_FILE"

# Store original for restoration
cp "$VERSIONS_FILE" "${VERSIONS_FILE}.bak"

# Downgrade aws provider to simulate old-version deployment
sed -i 's/version = "~> 5.0"/version = "~> 4.67"/' "$VERSIONS_FILE"

echo "[drift] Modified provider constraint:"
grep 'version.*aws' "$VERSIONS_FILE"
echo ""
echo "[drift] Run: terraform init -upgrade -reconfigure"
echo "[drift] Then: terraform plan"
echo "[drift] Version drift introduced. Restore with: cp ${VERSIONS_FILE}.bak ${VERSIONS_FILE}"
