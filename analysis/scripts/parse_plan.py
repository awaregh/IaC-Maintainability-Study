#!/usr/bin/env python3
"""
parse_plan.py - Parse terraform plan JSON output and extract maintainability metrics.

Usage:
  terraform plan -out=plan.binary
  terraform show -json plan.binary > plan.json
  python3 parse_plan.py plan.json [--output results/experiments/plan_metrics.json]

Extracts:
  - resources to add/change/destroy
  - change surface area (distinct resource types affected)
  - affected modules
  - blast radius estimate
  - per-resource change details
"""

import argparse
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path
from datetime import datetime, timezone


def load_plan(path: str) -> dict:
    """Load and validate a terraform show -json plan file."""
    p = Path(path)
    if not p.exists():
        print(f"ERROR: File not found: {path}", file=sys.stderr)
        sys.exit(1)
    with open(p) as f:
        data = json.load(f)
    if "format_version" not in data:
        print("WARNING: Missing format_version; this may not be a valid plan JSON.", file=sys.stderr)
    return data


def extract_resource_changes(plan: dict) -> list[dict]:
    """Extract resource_changes array, handling both full and partial plans."""
    changes = plan.get("resource_changes", [])
    if not changes:
        # Check for planned_values as fallback (partial plan / older format)
        pv = plan.get("planned_values", {}).get("root_module", {})
        resources = pv.get("resources", [])
        # Convert to pseudo-change format
        changes = [
            {
                "address": r.get("address", ""),
                "type": r.get("type", ""),
                "module_address": r.get("module_address", ""),
                "change": {"actions": ["create"]},
            }
            for r in resources
        ]
    return changes


def compute_metrics(changes: list[dict]) -> dict:
    """Compute maintainability metrics from resource changes."""
    action_counts = Counter()
    resource_types = set()
    affected_modules = set()
    changes_by_action = defaultdict(list)

    for rc in changes:
        actions = rc.get("change", {}).get("actions", [])
        resource_type = rc.get("type", "unknown")
        address = rc.get("address", "")
        module_address = rc.get("module_address", "") or "root"

        # Normalize no-op
        if actions == ["no-op"]:
            action_counts["no_op"] += 1
            continue

        for action in actions:
            action_counts[action] += 1

        resource_types.add(resource_type)
        affected_modules.add(module_address)
        changes_by_action[",".join(sorted(actions))].append(
            {
                "address": address,
                "type": resource_type,
                "module": module_address,
            }
        )

    total_changes = (
        action_counts.get("create", 0)
        + action_counts.get("update", 0)
        + action_counts.get("delete", 0)
        + action_counts.get("replace", 0)
    )

    # Blast radius: total resources affected (create + update + delete + replace)
    blast_radius = total_changes

    # Change surface area: number of distinct resource types affected
    change_surface_area = len(resource_types)

    # Disruption score: weighted sum (delete/replace are more disruptive)
    disruption_score = (
        action_counts.get("create", 0) * 1
        + action_counts.get("update", 0) * 2
        + action_counts.get("delete", 0) * 5
        + action_counts.get("replace", 0) * 5
    )

    return {
        "summary": {
            "total_changes": total_changes,
            "to_add": action_counts.get("create", 0),
            "to_change": action_counts.get("update", 0),
            "to_destroy": action_counts.get("delete", 0),
            "to_replace": action_counts.get("replace", 0),
            "no_op": action_counts.get("no_op", 0),
        },
        "change_surface_area": change_surface_area,
        "affected_resource_types": sorted(resource_types),
        "affected_module_count": len(affected_modules),
        "affected_modules": sorted(affected_modules),
        "blast_radius": blast_radius,
        "disruption_score": disruption_score,
        "changes_by_action": {k: v for k, v in changes_by_action.items()},
    }


def extract_provider_info(plan: dict) -> dict:
    """Extract provider configuration for version drift detection."""
    config = plan.get("configuration", {})
    provider_config = config.get("provider_config", {})
    providers = {}
    for name, cfg in provider_config.items():
        providers[name] = {
            "version_constraint": cfg.get("version_constraint", ""),
            "expressions": {
                k: v for k, v in cfg.get("expressions", {}).items() if k != "access_key"
            },
        }
    return providers


def extract_state_drift_signals(plan: dict) -> dict:
    """Identify signals that may indicate drift from prior state."""
    prior_state = plan.get("prior_state", {})
    resource_drift = plan.get("resource_drift", [])

    drift_items = []
    for drift in resource_drift:
        drift_items.append(
            {
                "address": drift.get("address", ""),
                "type": drift.get("type", ""),
                "change_type": drift.get("change", {}).get("actions", []),
            }
        )

    return {
        "drift_detected": len(drift_items) > 0,
        "drift_count": len(drift_items),
        "drift_items": drift_items,
        "prior_state_serial": prior_state.get("serial", None),
        "prior_state_version": prior_state.get("terraform_version", None),
    }


def main():
    parser = argparse.ArgumentParser(
        description="Parse terraform plan JSON output and extract maintainability metrics."
    )
    parser.add_argument(
        "plan_file",
        help="Path to the JSON output of `terraform show -json <plan.binary>`",
    )
    parser.add_argument(
        "--output",
        "-o",
        default=None,
        help="Path to write JSON metrics output (default: print to stdout)",
    )
    parser.add_argument(
        "--variant",
        "-v",
        default="unknown",
        help="Reference system variant name (e.g. monolithic, small_composable)",
    )
    parser.add_argument(
        "--scenario",
        "-s",
        default=None,
        help="Drift scenario name if applicable",
    )
    parser.add_argument(
        "--pretty",
        action="store_true",
        default=True,
        help="Pretty-print JSON output (default: True)",
    )
    args = parser.parse_args()

    plan = load_plan(args.plan_file)

    changes = extract_resource_changes(plan)
    metrics = compute_metrics(changes)
    providers = extract_provider_info(plan)
    drift_signals = extract_state_drift_signals(plan)

    result = {
        "variant": args.variant,
        "scenario": args.scenario,
        "analyzed_at": datetime.now(timezone.utc).isoformat(),
        "plan_file": str(Path(args.plan_file).resolve()),
        "terraform_version": plan.get("terraform_version", "unknown"),
        "format_version": plan.get("format_version", "unknown"),
        "metrics": metrics,
        "providers": providers,
        "drift_signals": drift_signals,
    }

    output_json = json.dumps(result, indent=2 if args.pretty else None)

    if args.output:
        out_path = Path(args.output)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(output_json)
        print(f"Metrics written to {out_path}", file=sys.stderr)
    else:
        print(output_json)

    # Print summary to stderr
    m = metrics
    print("\n── Plan Metrics Summary ──────────────────────────", file=sys.stderr)
    print(f"  Variant:              {args.variant}", file=sys.stderr)
    print(f"  Resources to add:     {m['summary']['to_add']}", file=sys.stderr)
    print(f"  Resources to change:  {m['summary']['to_change']}", file=sys.stderr)
    print(f"  Resources to destroy: {m['summary']['to_destroy']}", file=sys.stderr)
    print(f"  Resources to replace: {m['summary']['to_replace']}", file=sys.stderr)
    print(f"  Change surface area:  {m['change_surface_area']} resource types", file=sys.stderr)
    print(f"  Blast radius:         {m['blast_radius']} resources", file=sys.stderr)
    print(f"  Disruption score:     {m['disruption_score']}", file=sys.stderr)
    print(f"  Affected modules:     {m['affected_module_count']}", file=sys.stderr)
    print(f"  Drift detected:       {drift_signals['drift_detected']}", file=sys.stderr)
    print("──────────────────────────────────────────────────", file=sys.stderr)


if __name__ == "__main__":
    main()
