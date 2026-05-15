#!/usr/bin/env python3
"""Render an evidence-first visual dashboard for one kernel profile.

The figure intentionally combines several views instead of a single generic bar
chart: utilization bars, bottleneck scores, optimization direction, hotspot
dot-matrix, optional history trend, and run context. Missing artifacts degrade
to clear placeholders rather than failing the report.
"""
from __future__ import annotations

import argparse
import csv
import importlib.util
import json
import math
import re
import sys
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple

REQUIRED = ["matplotlib", "yaml"]
missing = [pkg for pkg in REQUIRED if importlib.util.find_spec(pkg) is None]
if missing:
    print("Missing Python packages: " + ", ".join(missing), file=sys.stderr)
    print("Install with: python -m pip install matplotlib pyyaml", file=sys.stderr)
    sys.exit(3)

import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle
import yaml

NUM_RE = re.compile(r"[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?")

RAW_PATTERNS = {
    "duration": re.compile(r"duration|time", re.I),
    "sm_throughput_pct": re.compile(r"sm.*throughput.*pct|sm__throughput", re.I),
    "memory_throughput_pct": re.compile(r"memory.*throughput.*pct|mem.*throughput", re.I),
    "dram_throughput_pct": re.compile(r"dram.*throughput.*pct|dram__throughput", re.I),
    "l2_throughput_pct": re.compile(r"l2.*throughput|lts__throughput", re.I),
    "l1tex_throughput_pct": re.compile(r"l1tex.*throughput|l1/tex.*throughput", re.I),
    "achieved_occupancy_pct": re.compile(r"achieved.*occupancy", re.I),
    "theoretical_occupancy_pct": re.compile(r"theoretical.*occupancy", re.I),
    "l2_hit_rate_pct": re.compile(r"l2.*hit", re.I),
    "l1tex_hit_rate_pct": re.compile(r"l1.*hit|tex.*hit", re.I),
    "bank_conflicts": re.compile(r"bank.*conflict", re.I),
    "local_memory": re.compile(r"local memory|spill", re.I),
    "ipc": re.compile(r"\bipc\b|inst.*cycle", re.I),
}


def number(value: Any) -> Optional[float]:
    if value is None:
        return None
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if math.isnan(float(value)):
            return None
        return float(value)
    match = NUM_RE.search(str(value).replace(",", ""))
    return float(match.group(0)) if match else None


def clamp(value: float, low: float = 0.0, high: float = 100.0) -> float:
    return max(low, min(high, value))


def read_yaml(path: Path) -> Dict[str, Any]:
    if not path.exists():
        return {}
    try:
        return yaml.safe_load(path.read_text(encoding="utf-8-sig")) or {}
    except Exception:
        return {}


def read_json(path: Path) -> Dict[str, Any]:
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def parse_csv_rows(path: Path) -> Iterable[List[str]]:
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except Exception:
        return []
    rows = []
    for line in text.splitlines():
        if not line.strip() or line.startswith("=="):
            continue
        try:
            row = next(csv.reader([line]))
        except Exception:
            continue
        if row:
            rows.append(row)
    return rows


def last_number(row: Iterable[Any]) -> Optional[float]:
    for cell in reversed(list(row)):
        val = number(cell)
        if val is not None:
            return val
    return None


def metric_keys(text: str) -> List[str]:
    return [key for key, pat in RAW_PATTERNS.items() if pat.search(text)]


def collect_columnar_rows(rows: List[List[str]]) -> Dict[str, List[float]]:
    values: Dict[str, List[float]] = {}
    for idx, header in enumerate(rows):
        metric_cols: List[Tuple[int, str]] = []
        seen = set()
        for col, cell in enumerate(header):
            for key in metric_keys(str(cell)):
                token = (col, key)
                if token not in seen:
                    metric_cols.append(token)
                    seen.add(token)
        if not metric_cols:
            continue
        for col, key in metric_cols:
            vals = []
            for row in rows[idx + 1:idx + 25]:
                if col >= len(row):
                    continue
                val = number(row[col])
                if val is not None:
                    vals.append(val)
            if vals:
                values.setdefault(key, []).extend(vals)
    return values


def collect_raw_metrics(details: Path) -> Dict[str, float]:
    values: Dict[str, List[float]] = {}
    for csv_path in sorted(details.glob("*_raw.csv")):
        rows = list(parse_csv_rows(csv_path))
        columnar_values = collect_columnar_rows(rows)
        values.update({k: values.get(k, []) + v for k, v in columnar_values.items()})
        columnar_keys = set(columnar_values)
        for row in rows:
            joined = " ".join(map(str, row))
            val = last_number(row)
            if val is None:
                continue
            for key in metric_keys(joined):
                if key not in columnar_keys:
                    values.setdefault(key, []).append(val)
    return {k: sum(v) / len(v) for k, v in values.items() if v}


def load_metrics(report_dir: Path) -> Dict[str, float]:
    details = report_dir / "details"
    metrics = {k: v for k, v in read_json(details / "metrics_summary.json").items() if number(v) is not None}
    raw_metrics = collect_raw_metrics(details)
    if raw_metrics:
        metrics.update(raw_metrics)
    return {k: float(number(v)) for k, v in metrics.items() if number(v) is not None}


def load_hotspots(report_dir: Path) -> List[Dict[str, str]]:
    path = report_dir / "details" / "source_hotspots.csv"
    if not path.exists():
        return []
    try:
        with path.open(newline="", encoding="utf-8", errors="replace") as fh:
            return [dict(row) for row in csv.DictReader(fh)]
    except Exception:
        return []


def load_history(report_dir: Path, kernel_name: str, metric: str) -> List[Tuple[str, float]]:
    root = report_dir.parent
    prefix = kernel_name or report_dir.name.split("_20")[0]
    points: List[Tuple[str, float]] = []
    if not root.exists():
        return points
    for candidate in sorted(p for p in root.iterdir() if p.is_dir() and p.name.startswith(prefix)):
        summary = read_json(candidate / "details" / "metrics_summary.json")
        val = number(summary.get(metric))
        if val is not None:
            label = candidate.name.replace(prefix, "").strip("_") or candidate.name
            points.append((label[-13:] if len(label) > 13 else label, val))
    return points[-8:]


def score_bottlenecks(metrics: Dict[str, float], hotspots: List[Dict[str, str]]) -> Dict[str, float]:
    sm = metrics.get("sm_throughput_pct")
    mem = metrics.get("memory_throughput_pct") or metrics.get("dram_throughput_pct")
    occ = metrics.get("achieved_occupancy_pct")
    theo = metrics.get("theoretical_occupancy_pct")
    ipc = metrics.get("ipc")
    l2_hit = metrics.get("l2_hit_rate_pct")
    l1_hit = metrics.get("l1tex_hit_rate_pct")
    bank = metrics.get("bank_conflicts")
    local = metrics.get("local_memory")

    scores = {
        "Memory bandwidth": max(mem or 0, 100 - (l2_hit or 100), 100 - (l1_hit or 100)) * 0.75,
        "Compute pipeline": (sm or 0) * 0.75,
        "Occupancy/resource": max(0, 80 - (occ or 80), (theo or 0) - (occ or theo or 0)) * 1.05,
        "Latency/scheduler": max(0, 55 - ((ipc or 1.0) * 25), 45 - (sm or 45), 45 - (mem or 45)),
        "Memory access": max(bank or 0, local or 0, 100 - (l2_hit or 100), 100 - (l1_hit or 100)),
        "Sync/source stalls": 0.0,
    }
    for row in hotspots:
        text = " ".join(str(v) for v in row.values()).lower()
        if "barrier" in text or "sync" in text or "stall" in text:
            scores["Sync/source stalls"] += 14
        if "bank" in text or "local" in text or "spill" in text:
            scores["Memory access"] += 10
    return {k: clamp(v) for k, v in scores.items()}


def recommendations(scores: Dict[str, float], metrics: Dict[str, float]) -> List[Tuple[str, str, float]]:
    ordered = sorted(scores.items(), key=lambda item: item[1], reverse=True)
    result = []
    for name, score in ordered[:4]:
        if name == "Memory bandwidth":
            action = "Improve coalescing, reuse, cache locality; inspect DRAM/L2 sectors."
        elif name == "Compute pipeline":
            action = "Inspect instruction mix, tensor/FMA use, unroll and pipeline balance."
        elif name == "Occupancy/resource":
            action = "Check registers, shared memory, block size, active warps per SM."
        elif name == "Latency/scheduler":
            action = "Reduce dependency chains; increase eligible warps and hide latency."
        elif name == "Memory access":
            action = "Fix bank conflicts, spills/local memory, low cache hit rate."
        else:
            action = "Map stalls to source/SASS and reduce synchronization pressure."
        result.append((name, action, score))
    return result


def metric_label(key: str) -> str:
    return {
        "sm_throughput_pct": "SM",
        "memory_throughput_pct": "Memory",
        "dram_throughput_pct": "DRAM",
        "l2_throughput_pct": "L2",
        "l1tex_throughput_pct": "L1/TEX",
        "achieved_occupancy_pct": "Ach. Occ",
        "theoretical_occupancy_pct": "Theo. Occ",
        "l2_hit_rate_pct": "L2 Hit",
        "l1tex_hit_rate_pct": "L1 Hit",
    }.get(key, key.replace("_", " "))


def color_for(value: float) -> str:
    if value >= 80:
        return "#c2410c"
    if value >= 55:
        return "#f59e0b"
    if value >= 30:
        return "#2563eb"
    return "#64748b"


def draw_placeholder(ax, title: str, message: str):
    ax.set_title(title, loc="left", fontweight="bold")
    ax.axis("off")
    ax.text(0.5, 0.5, message, ha="center", va="center", color="#64748b", fontsize=10)


def draw_utilization(ax, metrics: Dict[str, float]):
    keys = [
        "sm_throughput_pct",
        "memory_throughput_pct",
        "dram_throughput_pct",
        "l2_throughput_pct",
        "l1tex_throughput_pct",
        "achieved_occupancy_pct",
    ]
    present = [(metric_label(k), clamp(metrics[k])) for k in keys if k in metrics]
    if not present:
        draw_placeholder(ax, "Utilization", "No utilization metrics found")
        return
    labels, vals = zip(*present)
    bars = ax.bar(labels, vals, color=[color_for(v) for v in vals], edgecolor="#0f172a", linewidth=0.5)
    ax.axhspan(70, 100, color="#fee2e2", alpha=0.45, zorder=0)
    ax.axhspan(35, 70, color="#fef3c7", alpha=0.35, zorder=0)
    ax.set_ylim(0, 100)
    ax.set_ylabel("% of peak / occupancy")
    ax.set_title("Utilization Bars", loc="left", fontweight="bold")
    ax.tick_params(axis="x", rotation=20)
    for bar, val in zip(bars, vals):
        ax.text(bar.get_x() + bar.get_width() / 2, val + 2, f"{val:.0f}", ha="center", fontsize=8)


def draw_bottleneck_scores(ax, scores: Dict[str, float]):
    items = sorted(scores.items(), key=lambda item: item[1])
    labels = [x[0] for x in items]
    vals = [x[1] for x in items]
    ax.barh(labels, vals, color=[color_for(v) for v in vals])
    ax.set_xlim(0, 100)
    ax.set_title("Bottleneck Score", loc="left", fontweight="bold")
    ax.set_xlabel("Higher means more likely")
    for idx, val in enumerate(vals):
        ax.text(val + 1, idx, f"{val:.0f}", va="center", fontsize=8)


def draw_recommendations(ax, recs: List[Tuple[str, str, float]]):
    ax.set_title("Optimization Direction", loc="left", fontweight="bold")
    ax.axis("off")
    if not recs:
        ax.text(0.5, 0.5, "No recommendations without metrics", ha="center", va="center", color="#64748b")
        return
    y = 0.88
    for idx, (name, action, score) in enumerate(recs, 1):
        ax.add_patch(Rectangle((0.02, y - 0.075), 0.04, 0.05, color=color_for(score), transform=ax.transAxes))
        ax.text(0.08, y, f"{idx}. {name} ({score:.0f})", transform=ax.transAxes, fontweight="bold", va="top")
        ax.text(0.08, y - 0.08, action, transform=ax.transAxes, fontsize=9, va="top", wrap=True)
        y -= 0.22


def draw_hotspot_matrix(ax, hotspots: List[Dict[str, str]]):
    ax.set_title("Source / SASS Hotspot Matrix", loc="left", fontweight="bold")
    if not hotspots:
        ax.axis("off")
        ax.text(0.5, 0.5, "No source_hotspots.csv data", ha="center", va="center", color="#64748b")
        return
    classes = ["memory", "compute", "occupancy", "latency", "sync", "unknown"]
    rows = hotspots[:8]
    xs, ys, sizes, colors = [], [], [], []
    for y, row in enumerate(rows):
        text = " ".join(str(v) for v in row.values()).lower()
        value = number(row.get("value")) or 1.0
        for x, cls in enumerate(classes):
            hit = cls in text or (cls == "sync" and ("barrier" in text or "stall" in text))
            if hit or cls == "unknown":
                xs.append(x)
                ys.append(y)
                sizes.append(35 + min(abs(value), 100) * (1.5 if hit else 0.4))
                colors.append(color_for(75 if hit else 20))
                if hit:
                    break
    ax.scatter(xs, ys, s=sizes, c=colors, alpha=0.85, edgecolors="#0f172a", linewidths=0.4)
    labels = []
    for row in rows:
        src = row.get("source_file") or row.get("function") or row.get("sass_opcode") or "hotspot"
        line = row.get("line")
        labels.append(f"{Path(str(src)).name}:{line}" if line else str(src)[:24])
    ax.set_xticks(range(len(classes)), [c.title() for c in classes], rotation=20)
    ax.set_yticks(range(len(rows)), labels)
    ax.invert_yaxis()
    ax.grid(axis="x", alpha=0.2)


def draw_history(ax, report_dir: Path, kernel_name: str, metrics: Dict[str, float]):
    metric = "duration" if "duration" in metrics else "sm_throughput_pct"
    points = load_history(report_dir, kernel_name, metric)
    ax.set_title("Recent Trend", loc="left", fontweight="bold")
    if len(points) < 2:
        fallback_keys = [
            "sm_throughput_pct",
            "memory_throughput_pct",
            "dram_throughput_pct",
            "achieved_occupancy_pct",
            "l2_hit_rate_pct",
            "l1tex_hit_rate_pct",
        ]
        current = [(metric_label(k), clamp(metrics[k])) for k in fallback_keys if k in metrics]
        if len(current) < 2:
            ax.axis("off")
            ax.text(0.5, 0.5, "Need metrics or previous profiles for trend line", ha="center", va="center", color="#64748b")
            return
        labels, vals = zip(*current)
        ax.plot(range(len(vals)), vals, marker="o", color="#2563eb", linewidth=2.0)
        ax.fill_between(range(len(vals)), vals, alpha=0.12, color="#2563eb")
        ax.set_xticks(range(len(labels)), labels, rotation=25, ha="right")
        ax.set_ylabel("Current metric %")
        ax.set_ylim(0, 100)
        ax.grid(alpha=0.25)
        ax.text(0.02, 0.92, "Current profile metric line", transform=ax.transAxes, color="#64748b", fontsize=8)
        return
    labels, vals = zip(*points)
    ax.plot(range(len(vals)), vals, marker="o", color="#2563eb", linewidth=2.0)
    ax.fill_between(range(len(vals)), vals, alpha=0.12, color="#2563eb")
    ax.set_xticks(range(len(labels)), labels, rotation=25, ha="right")
    ax.set_ylabel(metric_label(metric))
    ax.grid(alpha=0.25)


def draw_context(ax, manifest: Dict[str, Any], report_dir: Path, metrics: Dict[str, float], scores: Dict[str, float]):
    ax.set_title("Run Context", loc="left", fontweight="bold")
    ax.axis("off")
    kernel = manifest.get("kernel", {}) if isinstance(manifest.get("kernel"), dict) else {}
    profiling = manifest.get("profiling", {}) if isinstance(manifest.get("profiling"), dict) else {}
    privilege = manifest.get("privilege", {}) if isinstance(manifest.get("privilege"), dict) else {}
    top = max(scores.items(), key=lambda item: item[1])[0] if scores else "unknown"
    lines = [
        f"Profile: {manifest.get('profile_id') or report_dir.name}",
        f"Kernel: {kernel.get('name') or 'unknown'}",
        f"Filter: {kernel.get('filter') or 'unknown'}",
        f"Stages: {profiling.get('stages') or 'unknown'}",
        f"Launch: skip={profiling.get('warmup_skip', '')}, count={profiling.get('launch_count', '')}",
        f"Privilege: sudo={privilege.get('sudo_requested', False)}",
        f"Top bottleneck: {top}",
    ]
    if "duration" in metrics:
        lines.append(f"Duration: {metrics['duration']:.3g}")
    ax.text(0.02, 0.92, "\n".join(lines), transform=ax.transAxes, va="top", fontsize=10)


def resolve_args(argv: List[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("legacy", nargs="*", help="Legacy positional mode: final_report.md details output.png")
    parser.add_argument("--report-dir", type=Path)
    parser.add_argument("--output", type=Path)
    ns = parser.parse_args(argv)
    if ns.report_dir and ns.output:
        return ns
    if len(ns.legacy) == 3:
        details = Path(ns.legacy[1])
        ns.report_dir = details.parent
        ns.output = Path(ns.legacy[2])
        return ns
    parser.error("Use --report-dir DIR --output PNG, or legacy: final_report.md details output.png")


def main(argv: Optional[List[str]] = None) -> int:
    args = resolve_args(argv or sys.argv[1:])
    report_dir: Path = args.report_dir
    output: Path = args.output
    details = report_dir / "details"

    manifest = read_yaml(report_dir / "run_manifest.yaml")
    metrics = load_metrics(report_dir)
    hotspots = load_hotspots(report_dir)
    scores = score_bottlenecks(metrics, hotspots)
    recs = recommendations(scores, metrics)
    kernel = manifest.get("kernel", {}) if isinstance(manifest.get("kernel"), dict) else {}
    kernel_name = str(kernel.get("name") or report_dir.name)

    output.parent.mkdir(parents=True, exist_ok=True)
    plt.rcParams.update({
        "font.size": 9,
        "axes.edgecolor": "#cbd5e1",
        "axes.labelcolor": "#334155",
        "xtick.color": "#334155",
        "ytick.color": "#334155",
        "figure.facecolor": "#f8fafc",
        "axes.facecolor": "#ffffff",
    })

    fig = plt.figure(figsize=(18, 11), constrained_layout=True)
    grid = fig.add_gridspec(3, 3, height_ratios=[1.05, 1.0, 0.95])
    fig.suptitle(f"Kernel Performance Diagnosis - {kernel_name}", fontsize=20, fontweight="bold", x=0.02, ha="left")

    draw_utilization(fig.add_subplot(grid[0, 0]), metrics)
    draw_bottleneck_scores(fig.add_subplot(grid[0, 1]), scores)
    draw_recommendations(fig.add_subplot(grid[0, 2]), recs)
    draw_hotspot_matrix(fig.add_subplot(grid[1, :2]), hotspots)
    draw_history(fig.add_subplot(grid[1, 2]), report_dir, kernel_name, metrics)
    draw_context(fig.add_subplot(grid[2, 0]), manifest, report_dir, metrics, scores)

    ax = fig.add_subplot(grid[2, 1:])
    ax.set_title("Metric Snapshot", loc="left", fontweight="bold")
    ax.axis("off")
    if metrics:
        snapshot_keys = [
            "duration", "sm_throughput_pct", "memory_throughput_pct", "dram_throughput_pct",
            "achieved_occupancy_pct", "theoretical_occupancy_pct", "l2_hit_rate_pct",
            "l1tex_hit_rate_pct", "ipc", "registers_per_thread", "bank_conflicts",
        ]
        rows = [(metric_label(k), metrics[k]) for k in snapshot_keys if k in metrics]
        cell_text = [[name, f"{val:.3g}"] for name, val in rows[:10]]
        table = ax.table(cellText=cell_text, colLabels=["Metric", "Value"], loc="center", cellLoc="left")
        table.auto_set_font_size(False)
        table.set_fontsize(9)
        table.scale(1, 1.3)
    else:
        ax.text(0.5, 0.5, f"No metrics found in {details}", ha="center", va="center", color="#64748b")

    fig.savefig(output, dpi=180, bbox_inches="tight")
    print(f"Wrote {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
