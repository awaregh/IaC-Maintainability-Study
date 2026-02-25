#!/usr/bin/env python3
"""
generate_dependency_graph.py - Analyze terraform graph DOT output for coupling metrics.

Usage:
  terraform graph | python3 generate_dependency_graph.py --stdin
  python3 generate_dependency_graph.py graph.dot [--output graph_metrics.json]

Produces:
  - Node count, edge count, coupling score (E/N)
  - Hub nodes (high in-degree, indicating high fan-in coupling)
  - Leaf nodes (zero out-degree, likely resources)
  - Strongly connected component count
  - Graph density
  - Per-node degree statistics
  - Optional simplified graph description
"""

import argparse
import json
import re
import sys
from collections import defaultdict
from pathlib import Path
from datetime import datetime, timezone


def parse_dot(dot_content: str) -> tuple[set[str], list[tuple[str, str]]]:
    """
    Parse a DOT format graph into nodes and edges.
    Handles both double-quoted node names and bracketed attribute syntax.
    Returns (nodes, edges) where nodes is a set of node IDs.
    """
    nodes: set[str] = set()
    edges: list[tuple[str, str]] = []

    # Match edge declarations: "src" -> "dst" [attrs]
    edge_pattern = re.compile(r'"([^"]+)"\s*->\s*"([^"]+)"')
    # Match node declarations: "nodename" [attrs]
    node_pattern = re.compile(r'^\s*"([^"]+)"\s*\[', re.MULTILINE)

    for match in edge_pattern.finditer(dot_content):
        src, dst = match.group(1), match.group(2)
        # Filter out Terraform graph meta-nodes
        if src.startswith("[root]") or dst.startswith("[root]"):
            continue
        nodes.add(src)
        nodes.add(dst)
        edges.append((src, dst))

    for match in node_pattern.finditer(dot_content):
        node_name = match.group(1)
        if not node_name.startswith("[root]"):
            nodes.add(node_name)

    return nodes, edges


def build_adjacency(nodes: set[str], edges: list[tuple[str, str]]) -> dict:
    """Build in-degree and out-degree maps."""
    in_degree = defaultdict(int)
    out_degree = defaultdict(int)

    for src, dst in edges:
        out_degree[src] += 1
        in_degree[dst] += 1

    # Ensure all nodes appear in both maps
    for node in nodes:
        in_degree.setdefault(node, 0)
        out_degree.setdefault(node, 0)

    return {"in_degree": dict(in_degree), "out_degree": dict(out_degree)}


def identify_hub_nodes(in_degree: dict, threshold_percentile: float = 0.80) -> list[dict]:
    """
    Identify hub nodes: nodes with in-degree above the given percentile.
    High in-degree nodes are heavily depended upon and represent coupling hotspots.
    """
    if not in_degree:
        return []

    degrees = sorted(in_degree.values())
    n = len(degrees)
    threshold_idx = int(n * threshold_percentile)
    threshold_value = degrees[min(threshold_idx, n - 1)]

    hubs = [
        {"node": node, "in_degree": deg}
        for node, deg in in_degree.items()
        if deg >= threshold_value and deg > 0
    ]
    return sorted(hubs, key=lambda x: x["in_degree"], reverse=True)


def compute_graph_metrics(nodes: set[str], edges: list[tuple[str, str]]) -> dict:
    """Compute all graph-level coupling metrics."""
    n = len(nodes)
    e = len(edges)

    coupling_score = round(e / n, 4) if n > 0 else 0.0
    # Graph density: actual edges / possible edges in a directed graph
    max_edges = n * (n - 1)
    density = round(e / max_edges, 6) if max_edges > 0 else 0.0

    adj = build_adjacency(nodes, edges)
    in_degree = adj["in_degree"]
    out_degree = adj["out_degree"]

    # Hub nodes (high in-degree)
    hubs = identify_hub_nodes(in_degree, threshold_percentile=0.90)

    # Leaf nodes: out_degree == 0 (resources that are not depended upon by others)
    leaves = [n for n, d in out_degree.items() if d == 0]

    # Root nodes: in_degree == 0 (resources with no dependencies)
    roots = [n for n, d in in_degree.items() if d == 0]

    # Degree statistics
    all_degrees = [in_degree[nd] + out_degree[nd] for nd in nodes]
    avg_degree = round(sum(all_degrees) / len(all_degrees), 2) if all_degrees else 0.0
    max_degree = max(all_degrees) if all_degrees else 0
    min_degree = min(all_degrees) if all_degrees else 0

    # Detect potential circular references (simplified: check for symmetric edges)
    edge_set = set(edges)
    circular_pairs = [
        (src, dst) for src, dst in edges if (dst, src) in edge_set
    ]

    # Top 10 most depended-upon nodes
    top_depended = sorted(in_degree.items(), key=lambda x: x[1], reverse=True)[:10]

    return {
        "node_count": n,
        "edge_count": e,
        "coupling_score": coupling_score,
        "graph_density": density,
        "hub_node_count": len(hubs),
        "hub_nodes": hubs[:10],  # Top 10 hubs
        "leaf_node_count": len(leaves),
        "root_node_count": len(roots),
        "avg_degree": avg_degree,
        "max_degree": max_degree,
        "min_degree": min_degree,
        "circular_reference_pairs": len(circular_pairs),
        "top_depended_nodes": [
            {"node": node, "in_degree": deg} for node, deg in top_depended if deg > 0
        ],
    }


def classify_node_type(node_name: str) -> str:
    """Attempt to classify a Terraform graph node into a resource category."""
    if ".provider" in node_name or node_name.startswith("provider"):
        return "provider"
    if node_name.startswith("module."):
        return "module"
    if node_name.startswith("data."):
        return "data_source"
    if node_name.startswith("var."):
        return "variable"
    if node_name.startswith("output."):
        return "output"
    if node_name.startswith("local."):
        return "local"
    return "resource"


def generate_simplified_graph(
    nodes: set[str], edges: list[tuple[str, str]], max_nodes: int = 30
) -> dict:
    """
    Generate a simplified representation of the graph for documentation.
    Groups nodes by type and summarizes edge patterns.
    """
    type_groups = defaultdict(list)
    for node in nodes:
        ntype = classify_node_type(node)
        type_groups[ntype].append(node)

    # Count inter-type edge flows
    edge_flows: dict[tuple[str, str], int] = defaultdict(int)
    for src, dst in edges:
        src_type = classify_node_type(src)
        dst_type = classify_node_type(dst)
        edge_flows[(src_type, dst_type)] += 1

    return {
        "node_type_counts": {k: len(v) for k, v in type_groups.items()},
        "inter_type_flows": [
            {"from": src, "to": dst, "edge_count": count}
            for (src, dst), count in sorted(edge_flows.items(), key=lambda x: x[1], reverse=True)
        ],
        "sample_nodes": {
            ntype: sorted(node_list)[:5]
            for ntype, node_list in type_groups.items()
        },
    }


def main():
    parser = argparse.ArgumentParser(
        description="Analyze terraform graph DOT output for coupling and dependency metrics."
    )
    source_group = parser.add_mutually_exclusive_group(required=True)
    source_group.add_argument(
        "dot_file",
        nargs="?",
        help="Path to DOT file from `terraform graph`",
    )
    source_group.add_argument(
        "--stdin",
        action="store_true",
        help="Read DOT content from stdin (pipe from `terraform graph`)",
    )
    parser.add_argument(
        "--output",
        "-o",
        default=None,
        help="Path to write JSON output (default: print to stdout)",
    )
    parser.add_argument(
        "--variant",
        "-v",
        default="unknown",
        help="Reference system variant name",
    )
    parser.add_argument(
        "--simplified-graph",
        action="store_true",
        default=True,
        help="Include simplified graph description in output",
    )
    args = parser.parse_args()

    # Load DOT content
    if args.stdin:
        dot_content = sys.stdin.read()
    else:
        dot_path = Path(args.dot_file)
        if not dot_path.exists():
            print(f"ERROR: File not found: {args.dot_file}", file=sys.stderr)
            sys.exit(1)
        dot_content = dot_path.read_text()

    if not dot_content.strip():
        print("ERROR: Empty DOT content", file=sys.stderr)
        sys.exit(1)

    nodes, edges = parse_dot(dot_content)
    metrics = compute_graph_metrics(nodes, edges)

    result = {
        "variant": args.variant,
        "analyzed_at": datetime.now(timezone.utc).isoformat(),
        "graph_metrics": metrics,
    }

    if args.simplified_graph:
        result["simplified_graph"] = generate_simplified_graph(nodes, edges)

    output_json = json.dumps(result, indent=2)

    if args.output:
        out_path = Path(args.output)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(output_json)
        print(f"Graph metrics written to {out_path}", file=sys.stderr)
    else:
        print(output_json)

    # Summary to stderr
    m = metrics
    print("\n── Dependency Graph Summary ──────────────────────", file=sys.stderr)
    print(f"  Variant:         {args.variant}", file=sys.stderr)
    print(f"  Nodes:           {m['node_count']}", file=sys.stderr)
    print(f"  Edges:           {m['edge_count']}", file=sys.stderr)
    print(f"  Coupling score:  {m['coupling_score']}  (E/N)", file=sys.stderr)
    print(f"  Graph density:   {m['graph_density']}", file=sys.stderr)
    print(f"  Hub nodes:       {m['hub_node_count']}", file=sys.stderr)
    print(f"  Avg degree:      {m['avg_degree']}", file=sys.stderr)
    print(f"  Max degree:      {m['max_degree']}", file=sys.stderr)
    print("──────────────────────────────────────────────────", file=sys.stderr)

    if m["hub_nodes"]:
        print("  Top hub nodes (high in-degree):", file=sys.stderr)
        for hub in m["hub_nodes"][:5]:
            print(f"    [{hub['in_degree']:3d}] {hub['node']}", file=sys.stderr)


if __name__ == "__main__":
    main()
