#!/usr/bin/env bash
# run_experiment.sh - Orchestrate a full drift detection experiment
#
# Usage:
#   ./run_experiment.sh --system <path> --scenario <path> [--env <env>] [--no-apply]
#
# Steps:
#   1. terraform init + plan (baseline)
#   2. terraform apply (optional, requires AWS credentials)
#   3. Introduce drift scenario
#   4. terraform plan again (drift detection)
#   5. Record metrics
#   6. Cleanup / rollback via terraform apply
#
# Options:
#   --system     Path to reference system directory (required)
#   --scenario   Path to drift scenario directory (required)
#   --env        Environment name [default: dev]
#   --no-apply   Skip actual terraform apply (plan only mode)
#   --no-rollback  Skip rollback after experiment
#   --results-dir  Directory for results [default: results/experiments]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPTS_DIR="$REPO_ROOT/analysis/scripts"
RESULTS_BASE="$REPO_ROOT/results/experiments"

# ── Defaults ──────────────────────────────────────────────────────────────────
SYSTEM_PATH=""
SCENARIO_PATH=""
ENVIRONMENT="dev"
APPLY_ENABLED=true
ROLLBACK_ENABLED=true
TF_VARS_FILE=""

log() { echo "[$(date '+%Y-%m-%dT%H:%M:%S')] $*"; }
log_section() {
  echo ""
  echo "╔══════════════════════════════════════════════════╗"
  echo "║  $*"
  echo "╚══════════════════════════════════════════════════╝"
}
die() { echo "ERROR: $*" >&2; exit 1; }

# ── Parse arguments ───────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --system|-s)       SYSTEM_PATH="$2";    shift 2 ;;
    --scenario)        SCENARIO_PATH="$2";  shift 2 ;;
    --env|-e)          ENVIRONMENT="$2";    shift 2 ;;
    --no-apply)        APPLY_ENABLED=false; shift ;;
    --no-rollback)     ROLLBACK_ENABLED=false; shift ;;
    --results-dir)     RESULTS_BASE="$2";   shift 2 ;;
    --vars-file)       TF_VARS_FILE="$2";   shift 2 ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *) die "Unknown option: $1" ;;
  esac
done

[[ -n "$SYSTEM_PATH"   ]] || die "--system is required"
[[ -n "$SCENARIO_PATH" ]] || die "--scenario is required"
[[ -d "$SYSTEM_PATH"   ]] || die "System directory not found: $SYSTEM_PATH"
[[ -d "$SCENARIO_PATH" ]] || die "Scenario directory not found: $SCENARIO_PATH"

VARIANT=$(basename "$SYSTEM_PATH")
SCENARIO=$(basename "$SCENARIO_PATH")
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
EXPERIMENT_ID="${VARIANT}_${SCENARIO}_${ENVIRONMENT}_${TIMESTAMP}"
RESULTS_DIR="$RESULTS_BASE/$EXPERIMENT_ID"

mkdir -p "$RESULTS_DIR"

log "Starting experiment: $EXPERIMENT_ID"
log "  System:    $SYSTEM_PATH"
log "  Scenario:  $SCENARIO_PATH"
log "  Env:       $ENVIRONMENT"
log "  Results:   $RESULTS_DIR"

# ── Build tfvars args ─────────────────────────────────────────────────────────
TFVARS_ARGS=""
if [[ -n "$TF_VARS_FILE" && -f "$TF_VARS_FILE" ]]; then
  TFVARS_ARGS="-var-file=$TF_VARS_FILE"
elif [[ -f "$SYSTEM_PATH/envs/${ENVIRONMENT}.tfvars" ]]; then
  TFVARS_ARGS="-var-file=$SYSTEM_PATH/envs/${ENVIRONMENT}.tfvars"
fi

# ── Helper: run terraform command, capture timing ────────────────────────────
run_tf() {
  local label="$1"; shift
  local start_time end_time elapsed

  log "Running: terraform $*"
  start_time=$(date +%s%3N)
  if (cd "$SYSTEM_PATH" && terraform "$@") 2>&1 | tee "$RESULTS_DIR/terraform_${label}.log"; then
    end_time=$(date +%s%3N)
    elapsed=$((end_time - start_time))
    log "Completed '$label' in ${elapsed}ms"
    echo "$elapsed"
  else
    end_time=$(date +%s%3N)
    elapsed=$((end_time - start_time))
    log "FAILED '$label' after ${elapsed}ms"
    echo "-1"
    return 1
  fi
}

# ── Step 1: terraform init ────────────────────────────────────────────────────
log_section "Step 1: Terraform Init"
run_tf "init" init -backend=false -input=false -no-color 2>&1 || true

# ── Step 2: Baseline plan ─────────────────────────────────────────────────────
log_section "Step 2: Baseline Plan"
PLAN_BASELINE_FILE="$RESULTS_DIR/baseline.plan"
run_tf "baseline_plan" plan \
  -out="$PLAN_BASELINE_FILE" \
  -input=false \
  -no-color \
  ${TFVARS_ARGS} \
  2>&1 || true

# Convert baseline plan to JSON
if [[ -f "$PLAN_BASELINE_FILE" ]] && command -v terraform &>/dev/null; then
  (cd "$SYSTEM_PATH" && terraform show -json "$PLAN_BASELINE_FILE") > "$RESULTS_DIR/baseline_plan.json" 2>&1 || true
fi

# ── Step 3: Apply (if enabled) ────────────────────────────────────────────────
APPLY_TIME=-1
if [[ "$APPLY_ENABLED" == "true" ]]; then
  log_section "Step 3: Terraform Apply"
  APPLY_TIME=$(run_tf "apply" apply \
    -auto-approve \
    -input=false \
    -no-color \
    ${TFVARS_ARGS} \
    2>&1) || {
    log "Apply failed - continuing with plan-only drift detection"
    APPLY_ENABLED=false
  }
else
  log "Skipping apply (--no-apply mode)"
fi

# ── Step 4: Introduce drift ───────────────────────────────────────────────────
log_section "Step 4: Introducing Drift Scenario"
DRIFT_SCRIPT="$SCENARIO_PATH/introduce_drift.sh"
DRIFT_TIME=-1

if [[ -f "$DRIFT_SCRIPT" && -x "$DRIFT_SCRIPT" ]]; then
  drift_start=$(date +%s%3N)
  log "Executing drift script: $DRIFT_SCRIPT"

  DRIFT_ENV="$ENVIRONMENT" \
  DRIFT_NAME_PREFIX="${VARIANT}-${ENVIRONMENT}" \
  RESULTS_DIR="$RESULTS_DIR" \
    "$DRIFT_SCRIPT" 2>&1 | tee "$RESULTS_DIR/drift_introduction.log" || {
    log "WARNING: Drift introduction script returned non-zero exit code"
  }

  drift_end=$(date +%s%3N)
  DRIFT_TIME=$((drift_end - drift_start))
  log "Drift introduction completed in ${DRIFT_TIME}ms"
else
  log "WARNING: Drift script not found or not executable: $DRIFT_SCRIPT"
fi

# Wait a moment for AWS eventual consistency
if [[ "$APPLY_ENABLED" == "true" ]]; then
  log "Waiting 10s for AWS eventual consistency..."
  sleep 10
fi

# ── Step 5: Detect drift via plan ─────────────────────────────────────────────
log_section "Step 5: Drift Detection via terraform plan"
DRIFT_PLAN_FILE="$RESULTS_DIR/drift_detection.plan"
DETECTION_START=$(date +%s%3N)

run_tf "drift_plan" plan \
  -out="$DRIFT_PLAN_FILE" \
  -detailed-exitcode \
  -input=false \
  -no-color \
  ${TFVARS_ARGS} \
  2>&1 | tee "$RESULTS_DIR/drift_detection.log" || PLAN_EXIT_CODE=$?

DETECTION_END=$(date +%s%3N)
DETECTION_TIME=$((DETECTION_END - DETECTION_START))

# Exit codes: 0=no changes, 1=error, 2=changes detected
DRIFT_DETECTED=false
if [[ "${PLAN_EXIT_CODE:-0}" == "2" ]]; then
  DRIFT_DETECTED=true
  log "DRIFT DETECTED: terraform plan shows changes (exit code 2)"
elif [[ "${PLAN_EXIT_CODE:-0}" == "0" ]]; then
  log "No drift detected by terraform plan (exit code 0)"
fi

# Convert drift plan to JSON
if [[ -f "$DRIFT_PLAN_FILE" ]] && command -v terraform &>/dev/null; then
  (cd "$SYSTEM_PATH" && terraform show -json "$DRIFT_PLAN_FILE") > "$RESULTS_DIR/drift_plan.json" 2>&1 || true
fi

# Run scenario-specific detection script if available
DETECT_SCRIPT="$SCENARIO_PATH/detect_drift.sh"
if [[ -f "$DETECT_SCRIPT" && -x "$DETECT_SCRIPT" ]]; then
  log "Running scenario detection script..."
  DRIFT_ENV="$ENVIRONMENT" \
  DRIFT_NAME_PREFIX="${VARIANT}-${ENVIRONMENT}" \
    "$DETECT_SCRIPT" 2>&1 | tee "$RESULTS_DIR/scenario_detection.log" || true
fi

# ── Step 6: Parse plan metrics ────────────────────────────────────────────────
log_section "Step 6: Parsing Plan Metrics"
if [[ -f "$RESULTS_DIR/drift_plan.json" ]]; then
  python3 "$SCRIPTS_DIR/parse_plan.py" \
    "$RESULTS_DIR/drift_plan.json" \
    --variant "$VARIANT" \
    --scenario "$SCENARIO" \
    --output "$RESULTS_DIR/plan_metrics.json" \
    2>&1 || log "parse_plan.py failed - continuing"
fi

# Run structural metrics
python3 "$SCRIPTS_DIR/measure_metrics.sh" "$SYSTEM_PATH" 2>&1 || true
"$SCRIPTS_DIR/measure_metrics.sh" "$SYSTEM_PATH" 2>&1 | tee "$RESULTS_DIR/structural_metrics.log" || true

# ── Step 7: Rollback ──────────────────────────────────────────────────────────
if [[ "$APPLY_ENABLED" == "true" && "$ROLLBACK_ENABLED" == "true" ]]; then
  log_section "Step 7: Rollback (terraform apply)"
  run_tf "rollback" apply \
    -auto-approve \
    -input=false \
    -no-color \
    ${TFVARS_ARGS} \
    2>&1 | tee "$RESULTS_DIR/rollback.log" || log "WARNING: Rollback failed"
fi

# ── Step 8: Write experiment summary ─────────────────────────────────────────
log_section "Step 8: Writing Experiment Summary"
METADATA_FILE="$SCENARIO_PATH/metadata.json"
SCENARIO_METADATA="{}"
if [[ -f "$METADATA_FILE" ]]; then
  SCENARIO_METADATA=$(cat "$METADATA_FILE")
fi

cat > "$RESULTS_DIR/experiment_summary.json" << JSON
{
  "experiment_id": "$EXPERIMENT_ID",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "variant": "$VARIANT",
  "scenario": "$SCENARIO",
  "environment": "$ENVIRONMENT",
  "apply_enabled": $APPLY_ENABLED,
  "drift_detected": $DRIFT_DETECTED,
  "detection_latency_ms": $DETECTION_TIME,
  "apply_duration_ms": $APPLY_TIME,
  "drift_introduction_ms": $DRIFT_TIME,
  "plan_exit_code": ${PLAN_EXIT_CODE:-0},
  "results_dir": "$RESULTS_DIR",
  "scenario_metadata": $SCENARIO_METADATA
}
JSON

log "Experiment complete."
log "  Drift detected:         $DRIFT_DETECTED"
log "  Detection latency:      ${DETECTION_TIME}ms"
log "  Results saved to:       $RESULTS_DIR"
cat "$RESULTS_DIR/experiment_summary.json"
