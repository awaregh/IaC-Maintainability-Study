#!/usr/bin/env bash
# Detect provider version drift by comparing lock files across environments
set -euo pipefail

SYSTEM_PATH="${SYSTEM_PATH:-infra/reference_systems/monolithic}"
LOCK_FILE="$SYSTEM_PATH/.terraform.lock.hcl"

if [[ ! -f "$LOCK_FILE" ]]; then
  echo "[detect] No .terraform.lock.hcl found - run terraform init first"
  exit 1
fi

echo "[detect] Provider versions in lock file:"
grep -A3 'provider "registry.terraform.io' "$LOCK_FILE" | grep -E 'version|provider' || true

# Check if versions.tf and lock file agree
CONSTRAINT=$(grep -A1 'source.*hashicorp/aws' "$SYSTEM_PATH/versions.tf" | grep version | grep -oE '[0-9]+\.[0-9]+' | head -1)
LOCKED=$(grep -A5 'hashicorp/aws' "$LOCK_FILE" | grep 'version = ' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)

echo "[detect] Constraint (versions.tf): ~> $CONSTRAINT"
echo "[detect] Locked version:           $LOCKED"

if [[ -n "$LOCKED" && "$LOCKED" != "${CONSTRAINT}"* ]]; then
  echo "[detect] VERSION DRIFT DETECTED: locked version $LOCKED does not match constraint ~> $CONSTRAINT"
  exit 2
else
  echo "[detect] Provider versions appear consistent"
  exit 0
fi
