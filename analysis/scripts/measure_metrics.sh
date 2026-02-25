#!/usr/bin/env bash
# measure_metrics.sh - Measure IaC maintainability metrics for a reference system
# Usage: ./measure_metrics.sh <path_to_reference_system>
#
# Outputs a JSON file to /results/metrics/<variant_name>.json with:
#   - module_count
#   - coupling_score (edges/nodes from terraform graph)
#   - total_loc
#   - resource_blocks
#   - module_calls
#   - reuse_ratio
# Requires: terraform >= 1.5, jq, dot (graphviz)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RESULTS_DIR="$REPO_ROOT/results/metrics"

usage() {
  echo "Usage: $0 <path_to_reference_system>"
  echo ""
  echo "  <path_to_reference_system>  Path to the Terraform root directory to analyze."
  echo ""
  echo "Examples:"
  echo "  $0 infra/reference_systems/monolithic"
  echo "  $0 infra/reference_systems/small_composable"
  exit 1
}

log() { echo "[$(date '+%H:%M:%S')] $*" >&2; }
die() { echo "ERROR: $*" >&2; exit 1; }

[[ $# -lt 1 ]] && usage

SYSTEM_PATH="$1"
[[ -d "$SYSTEM_PATH" ]] || die "Directory not found: $SYSTEM_PATH"

VARIANT=$(basename "$SYSTEM_PATH")
OUTPUT_FILE="$RESULTS_DIR/${VARIANT}.json"

mkdir -p "$RESULTS_DIR"

# ── 1. Count total lines of Terraform code ────────────────────────────────────
log "Counting lines of code..."
TOTAL_LOC=$(find "$SYSTEM_PATH" -name "*.tf" -not -path "*/.terraform/*" | xargs wc -l 2>/dev/null | tail -1 | awk '{print $1}')
TOTAL_LOC=${TOTAL_LOC:-0}

# ── 2. Count resource blocks ──────────────────────────────────────────────────
log "Counting resource blocks..."
RESOURCE_BLOCKS=$(grep -r --include="*.tf" -c '^resource "' "$SYSTEM_PATH" 2>/dev/null | awk -F: '{sum+=$2} END{print sum}') || RESOURCE_BLOCKS=0
RESOURCE_BLOCKS=${RESOURCE_BLOCKS:-0}

# ── 3. Count module calls ─────────────────────────────────────────────────────
log "Counting module calls..."
MODULE_CALLS=$(grep -r --include="*.tf" -c '^module "' "$SYSTEM_PATH" 2>/dev/null | awk -F: '{sum+=$2} END{print sum}') || MODULE_CALLS=0
MODULE_CALLS=${MODULE_CALLS:-0}

# ── 4. Count distinct module directories ──────────────────────────────────────
log "Counting module directories..."
MODULE_COUNT=$(find "$SYSTEM_PATH" -name "main.tf" -not -path "*/.terraform/*" | wc -l)
MODULE_COUNT=$((MODULE_COUNT - 1))  # Subtract root module
MODULE_COUNT=$((MODULE_COUNT < 0 ? 0 : MODULE_COUNT))

# ── 5. Count data source blocks ───────────────────────────────────────────────
DATA_BLOCKS=$(grep -r --include="*.tf" -c '^data "' "$SYSTEM_PATH" 2>/dev/null | awk -F: '{sum+=$2} END{print sum}') || DATA_BLOCKS=0
DATA_BLOCKS=${DATA_BLOCKS:-0}

# ── 6. Count variable declarations ───────────────────────────────────────────
VARIABLE_COUNT=$(grep -r --include="*.tf" -c '^variable "' "$SYSTEM_PATH" 2>/dev/null | awk -F: '{sum+=$2} END{print sum}') || VARIABLE_COUNT=0
VARIABLE_COUNT=${VARIABLE_COUNT:-0}

# ── 7. Count output declarations ─────────────────────────────────────────────
OUTPUT_COUNT=$(grep -r --include="*.tf" -c '^output "' "$SYSTEM_PATH" 2>/dev/null | awk -F: '{sum+=$2} END{print sum}') || OUTPUT_COUNT=0
OUTPUT_COUNT=${OUTPUT_COUNT:-0}

# ── 8. Compute reuse ratio ────────────────────────────────────────────────────
if [[ "$RESOURCE_BLOCKS" -gt 0 ]]; then
  REUSE_RATIO=$(awk "BEGIN {printf \"%.4f\", $MODULE_CALLS / ($RESOURCE_BLOCKS + $MODULE_CALLS)}")
else
  REUSE_RATIO="0.0000"
fi

# ── 9. Coupling score from terraform graph ────────────────────────────────────
log "Computing coupling score via terraform graph..."
COUPLING_SCORE="null"
GRAPH_NODES=0
GRAPH_EDGES=0
GRAPH_AVAILABLE=false

# Try to find the root tf directory (handle layer-based variant)
ROOT_TF_DIR="$SYSTEM_PATH"
if [[ -d "$SYSTEM_PATH/root" ]]; then
  ROOT_TF_DIR="$SYSTEM_PATH/root"
fi

if command -v terraform &>/dev/null && command -v dot &>/dev/null; then
  TMPDIR_GRAPH=$(mktemp -d)
  trap 'rm -rf "$TMPDIR_GRAPH"' EXIT

  if (cd "$ROOT_TF_DIR" && terraform init -backend=false -input=false -no-color 2>/dev/null && \
      terraform graph -type=plan 2>/dev/null > "$TMPDIR_GRAPH/graph.dot"); then
    GRAPH_NODES=$(grep -c '"[a-zA-Z]' "$TMPDIR_GRAPH/graph.dot" 2>/dev/null || echo 0)
    GRAPH_EDGES=$(grep -c ' -> ' "$TMPDIR_GRAPH/graph.dot" 2>/dev/null || echo 0)
    if [[ "$GRAPH_NODES" -gt 0 ]]; then
      COUPLING_SCORE=$(awk "BEGIN {printf \"%.4f\", $GRAPH_EDGES / $GRAPH_NODES}")
      GRAPH_AVAILABLE=true
    fi
    log "Graph: nodes=$GRAPH_NODES, edges=$GRAPH_EDGES, coupling=$COUPLING_SCORE"
  else
    log "terraform graph failed (credentials or init issue); skipping coupling score"
  fi
else
  log "terraform or dot not available; estimating coupling from dependency patterns"
  # Estimate coupling by counting variable references that look like cross-resource refs
  CROSS_REFS=$(grep -r --include="*.tf" -ohE '\w+\.\w+\.\w+' "$SYSTEM_PATH" 2>/dev/null | wc -l || echo 0)
  if [[ "$RESOURCE_BLOCKS" -gt 0 ]]; then
    COUPLING_SCORE=$(awk "BEGIN {printf \"%.4f\", $CROSS_REFS / ($RESOURCE_BLOCKS + 1)}")
  fi
fi

# ── 10. Estimate change surface area (avg resources per logical module) ────────
if [[ "$MODULE_COUNT" -gt 0 ]]; then
  CHANGE_SURFACE=$(awk "BEGIN {printf \"%.2f\", $RESOURCE_BLOCKS / $MODULE_COUNT}")
else
  CHANGE_SURFACE=$RESOURCE_BLOCKS
fi

# ── 11. Write JSON output ─────────────────────────────────────────────────────
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

cat > "$OUTPUT_FILE" << JSON
{
  "variant": "$VARIANT",
  "measured_at": "$TIMESTAMP",
  "source_path": "$SYSTEM_PATH",
  "metrics": {
    "total_loc": $TOTAL_LOC,
    "resource_blocks": $RESOURCE_BLOCKS,
    "module_calls": $MODULE_CALLS,
    "module_count": $MODULE_COUNT,
    "data_blocks": $DATA_BLOCKS,
    "variable_count": $VARIABLE_COUNT,
    "output_count": $OUTPUT_COUNT,
    "reuse_ratio": $REUSE_RATIO,
    "coupling_score": $COUPLING_SCORE,
    "graph_nodes": $GRAPH_NODES,
    "graph_edges": $GRAPH_EDGES,
    "graph_available": $GRAPH_AVAILABLE,
    "estimated_change_surface": $CHANGE_SURFACE
  }
}
JSON

log "Metrics written to $OUTPUT_FILE"

# Pretty-print summary
echo ""
echo "════════════════════════════════════════════════"
echo "  Metrics for: $VARIANT"
echo "════════════════════════════════════════════════"
echo "  Total LOC:          $TOTAL_LOC"
echo "  Resource blocks:    $RESOURCE_BLOCKS"
echo "  Module calls:       $MODULE_CALLS"
echo "  Module count:       $MODULE_COUNT"
echo "  Variable decls:     $VARIABLE_COUNT"
echo "  Output decls:       $OUTPUT_COUNT"
echo "  Reuse ratio:        $REUSE_RATIO"
echo "  Coupling score:     $COUPLING_SCORE"
echo "  Change surface:     $CHANGE_SURFACE"
echo "════════════════════════════════════════════════"
