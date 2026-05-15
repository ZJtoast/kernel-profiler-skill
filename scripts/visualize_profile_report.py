#!/usr/bin/env python3
"""Create a compact visual summary for a kernel profile report directory.

The script is intentionally conservative: it reads CSV files if present and tries
common Nsight Compute metric names. Missing data is reported in the figure rather
than causing a hard failure.
"""
from __future__ import annotations

import argparse
import importlib.util
import sys
from pathlib import Path
from typing import Dict, Optional

REQUIRED = ["pandas", "matplotlib", "yaml"]
missing = [pkg for pkg in REQUIRED if importlib.util.find_spec(pkg) is None]
if missing:
    print("Missing Python packages: " + ", ".join(missing), file=sys.stderr)
    print("Install with: python -m pip install pandas matplotlib pyyaml", file=sys.stderr)
    sys.exit(3)

import pandas as pd
import matplotlib.pyplot as plt
import yaml

COMMON_METRICS = {
    "SM throughput %": [
        "sm__throughput.avg.pct_of_peak_sustained_elapsed",
        "sm__throughput.avg.pct_of_peak_sustained_active",
    ],
    "DRAM throughput %": [
        "dram__throughput.avg.pct_of_peak_sustained_elapsed",
        "dram__throughput.avg.pct_of_peak_sustained_active",
    ],
    "L2 throughput %": [
        "lts__throughput.avg.pct_of_peak_sustained_elapsed",
        "lts__throughput.avg.pct_of_peak_sustained_active",
    ],
    "L1/TEX throughput %": [
        "l1tex__throughput.avg.pct_of_peak_sustained_elapsed",
        "l1tex__throughput.avg.pct_of_peak_sustained_active",
    ],
    "Issued inst / cycle": [
        "smsp__inst_issued.avg.per_cycle_active",
    ],
    "Executed inst / cycle": [
        "smsp__inst_executed.avg.per_cycle_active",
    ],
}


def read_manifest(report_dir: Path) -> Dict:
    path = report_dir / "run_manifest.yaml"
    if not path.exists():
        return {}
    try:
        return yaml.safe_load(path.read_text()) or {}
    except Exception:
        return {}


def extract_metric_from_csv(csv_path: Path, metric_names) -> Optional[float]:
    try:
        df = pd.read_csv(csv_path)
    except Exception:
        return None
    if df.empty:
        return None

    # Nsight Compute CSV shapes differ by page/version. Try common columns.
    lower_cols = {c.lower(): c for c in df.columns}
    metric_col = None
    value_col = None
    for cand in ["metric name", "metric", "name"]:
        if cand in lower_cols:
            metric_col = lower_cols[cand]
            break
    for cand in ["metric value", "value", "avg", "sum"]:
        if cand in lower_cols:
            value_col = lower_cols[cand]
            break

    if metric_col and value_col:
        for name in metric_names:
            matches = df[df[metric_col].astype(str).str.contains(name, regex=False, na=False)]
            if not matches.empty:
                raw = str(matches.iloc[0][value_col]).replace(",", "").replace("%", "")
                try:
                    return float(raw)
                except ValueError:
                    continue

    # Fallback: search any cell for metric name, take nearest numeric cell in row.
    for _, row in df.iterrows():
        row_str = [str(x) for x in row.tolist()]
        if any(any(name in cell for name in metric_names) for cell in row_str):
            for cell in reversed(row_str):
                try:
                    return float(cell.replace(",", "").replace("%", ""))
                except ValueError:
                    pass
    return None


def collect_values(report_dir: Path) -> Dict[str, Optional[float]]:
    csvs = sorted((report_dir / "details").glob("*_raw.csv"))
    values: Dict[str, Optional[float]] = {}
    for label, names in COMMON_METRICS.items():
        val = None
        for csv_path in csvs:
            val = extract_metric_from_csv(csv_path, names)
            if val is not None:
                break
        values[label] = val
    return values


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--report-dir", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    report_dir: Path = args.report_dir
    manifest = read_manifest(report_dir)
    values = collect_values(report_dir)

    present = {k: v for k, v in values.items() if v is not None}

    args.output.parent.mkdir(parents=True, exist_ok=True)
    fig = plt.figure(figsize=(12, 7))
    ax = fig.add_axes([0.08, 0.20, 0.86, 0.58])

    title = manifest.get("profile_id") or report_dir.name
    fig.suptitle(f"Kernel Profile Summary: {title}", fontsize=16)

    if present:
        labels = list(present.keys())
        vals = list(present.values())
        ax.bar(labels, vals)
        ax.set_ylabel("Value")
        ax.set_title("Extracted profiler metrics")
        ax.tick_params(axis="x", rotation=30)
    else:
        ax.axis("off")
        ax.text(
            0.5,
            0.5,
            "No known raw metrics found.\nExport Nsight Compute raw CSV files into details/*_raw.csv.",
            ha="center",
            va="center",
            fontsize=13,
        )

    info = []
    if manifest:
        kernel = manifest.get("kernel", {}) if isinstance(manifest.get("kernel"), dict) else {}
        profiling = manifest.get("profiling", {}) if isinstance(manifest.get("profiling"), dict) else {}
        info.append(f"Backend: {manifest.get('backend', 'unknown')}")
        if kernel:
            info.append(f"Kernel: {kernel.get('name', '')} | Filter: {kernel.get('filter', '')}")
        if profiling:
            info.append(f"Launch window: skip={profiling.get('warmup_skip', '')}, count={profiling.get('launch_count', '')}")
    fig.text(0.08, 0.06, "\n".join(info), fontsize=10)

    fig.tight_layout(rect=[0, 0.10, 1, 0.92])
    fig.savefig(args.output, dpi=180)
    print(f"Wrote {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
