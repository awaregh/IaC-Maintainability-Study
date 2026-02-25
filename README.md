# IaC Maintainability Study

A comprehensive empirical study examining how structural design decisions in Terraform infrastructure-as-code affect long-term maintainability, drift susceptibility, and change management complexity.

## Overview

This repository contains six reference implementations of the same production-grade AWS infrastructure using different Terraform organizational strategies. Each variant implements identical functional requirements, enabling controlled comparison of maintainability metrics across patterns.

### Infrastructure Under Study

All six variants deploy:
- **VPC** with public and private subnets across 3 AZs
- **ECS Fargate** cluster and service
- **RDS PostgreSQL** (Multi-AZ in production)
- **S3** bucket with versioning and encryption
- **IAM** roles and least-privilege policies
- **CloudWatch** dashboards and alarms

### Reference System Variants

| Variant | Directory | Strategy |
|---|---|---|
| Monolithic | `infra/reference_systems/monolithic/` | All resources in one root module |
| Small Composable | `infra/reference_systems/small_composable/` | One module per AWS service |
| Domain-Based | `infra/reference_systems/domain_based/` | Modules grouped by business domain |
| Layer-Based | `infra/reference_systems/layer_based/` | Network → Compute → Data → Security → Observability layers |
| Workspace-Based | `infra/reference_systems/workspace_based/` | Single codebase, per-environment workspaces |
| State-Per-Stack | `infra/reference_systems/state_per_stack/` | Independent state files per logical stack |

## Repository Structure

```
.
├── README.md
├── paper/
│   ├── paper.md                    # Academic paper writeup
│   └── figures/                    # Generated figures (gitignored outputs)
├── infra/
│   └── reference_systems/
│       ├── monolithic/
│       ├── small_composable/
│       ├── domain_based/
│       ├── layer_based/
│       ├── workspace_based/
│       └── state_per_stack/
├── analysis/
│   ├── scripts/
│   │   ├── measure_metrics.sh      # Compute structural metrics
│   │   ├── parse_plan.py           # Analyze terraform plan output
│   │   ├── generate_dependency_graph.py
│   │   └── run_experiment.sh       # Orchestrate full experiment
│   └── notebooks/
│       └── maintainability_analysis.ipynb
├── drift_scenarios/
│   ├── taxonomy.md
│   ├── 01_out_of_band_change/
│   ├── 02_version_drift/
│   ├── 03_provider_default_drift/
│   ├── 04_data_source_nondeterminism/
│   ├── 05_partial_apply_state_issues/
│   └── 06_iam_config_drift/
├── docs/
│   ├── findings.md
│   └── recommendations.md
└── results/
    ├── metrics/
    └── experiments/
```

## Prerequisites

- Terraform >= 1.5.0
- AWS CLI >= 2.0 configured with appropriate credentials
- Python >= 3.10 (for analysis scripts)
- Jupyter Lab (for notebooks)
- `dot` (Graphviz) for dependency graph generation

```bash
pip install networkx matplotlib pandas jupyter jupyterlab
```

## Running the Experiments

### 1. Measure Structural Metrics

```bash
# Measure metrics for each reference system
for system in monolithic small_composable domain_based layer_based workspace_based state_per_stack; do
  ./analysis/scripts/measure_metrics.sh infra/reference_systems/$system
done
```

### 2. Run a Full Drift Experiment

```bash
# Full experiment against one variant
./analysis/scripts/run_experiment.sh \
  --system infra/reference_systems/small_composable \
  --scenario drift_scenarios/01_out_of_band_change \
  --env dev
```

### 3. Analyze Results

```bash
cd analysis/notebooks
jupyter lab maintainability_analysis.ipynb
```

## Metrics Collected

| Metric | Description |
|---|---|
| **Module Count** | Number of distinct modules |
| **Coupling Score** | Graph edge-to-node ratio (from `terraform graph`) |
| **Total LOC** | Lines of Terraform code |
| **Reuse Ratio** | Module calls / total resource blocks |
| **Change Surface** | Resources affected per typical change |
| **Drift Detection Time** | Time from drift introduction to detection |
| **Blast Radius** | Resources impacted by a change |

## Drift Scenarios

Six drift categories are studied:

1. **Out-of-Band Change** — Manual AWS console modifications
2. **Version Drift** — Provider or module version skew
3. **Provider Default Drift** — AWS service defaults changing
4. **Data Source Nondeterminism** — Unstable `data` source results
5. **Partial Apply / State Issues** — Interrupted applies leaving partial state
6. **IAM / Config Drift** — Policy and configuration mutations

## Key Findings

See [`docs/findings.md`](docs/findings.md) for full results and [`docs/recommendations.md`](docs/recommendations.md) for engineering guidance.

## Paper

The academic paper describing this study is at [`paper/paper.md`](paper/paper.md).

## License

MIT
