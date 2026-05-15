#!/usr/bin/env python3
"""Extract compact summaries from Nsight Compute CSV/text outputs.

The parser is deliberately tolerant because NCU CSV layout varies by version and selected page.
It creates compact artifacts for agent consumption to reduce token usage.
"""
from __future__ import annotations
import argparse, csv, json, re
from pathlib import Path
from statistics import mean

KEY_PATTERNS = {
    "duration": re.compile(r"duration|time", re.I),
    "sm_throughput_pct": re.compile(r"sm.*throughput.*pct|sm__throughput", re.I),
    "memory_throughput_pct": re.compile(r"memory.*throughput.*pct|dram__throughput|mem.*throughput", re.I),
    "dram_throughput_pct": re.compile(r"dram.*throughput.*pct|dram__throughput", re.I),
    "l2_throughput_pct": re.compile(r"l2.*throughput.*pct|lts__throughput", re.I),
    "l1tex_throughput_pct": re.compile(r"l1tex.*throughput|l1/tex.*throughput|l1tex__throughput", re.I),
    "achieved_occupancy_pct": re.compile(r"achieved.*occupancy", re.I),
    "theoretical_occupancy_pct": re.compile(r"theoretical.*occupancy", re.I),
    "registers_per_thread": re.compile(r"registers per thread|reg.*thread", re.I),
    "shared_memory": re.compile(r"shared memory|smem", re.I),
    "block_size": re.compile(r"block size|threads per block", re.I),
    "grid_size": re.compile(r"grid size|blocks", re.I),
    "l2_hit_rate_pct": re.compile(r"l2.*hit", re.I),
    "l1tex_hit_rate_pct": re.compile(r"l1.*hit|tex.*hit", re.I),
    "bank_conflicts": re.compile(r"bank.*conflict", re.I),
    "local_memory": re.compile(r"local memory|spill", re.I),
    "ipc": re.compile(r"\bipc\b|inst.*cycle", re.I),
}
NUM_RE=re.compile(r"[-+]?\d*\.?\d+(?:[eE][-+]?\d+)?")

def num(s):
    if s is None: return None
    m=NUM_RE.search(str(s).replace(',',''))
    return float(m.group(0)) if m else None

def parse_rows(path: Path):
    txt=path.read_text(errors='replace')
    rows=[]
    for line in txt.splitlines():
        if not line.strip() or line.startswith('=='): continue
        try:
            parsed=next(csv.reader([line]))
        except Exception:
            continue
        if len(parsed)>=2:
            rows.append(parsed)
    return rows

def last_num(row):
    for cell in reversed(row):
        val=num(cell)
        if val is not None:
            return val
    return None

def matching_keys(text):
    return [name for name, pat in KEY_PATTERNS.items() if pat.search(text)]

def extract_columnar(rows):
    """Parse NCU CSV pages where metric names are column headers.

    Recent raw exports can place metrics such as sm__throughput... in the CSV
    header and the values in later rows. Treating those headers as normal rows
    can produce pseudo-values from unrelated launch columns, so this path
    extracts values by column index and lets callers prefer it over row-wise
    fallback for overlapping metrics.
    """
    metrics={}
    raw=[]
    for idx, header in enumerate(rows):
        metric_cols=[]
        seen=set()
        for col, cell in enumerate(header):
            for key in matching_keys(str(cell)):
                token=(col,key)
                if token not in seen:
                    metric_cols.append(token)
                    seen.add(token)
        if not metric_cols:
            continue
        window=rows[idx+1:idx+25]
        if not window:
            continue
        for col, key in metric_cols:
            vals=[]
            for row in window:
                if col >= len(row):
                    continue
                val=num(row[col])
                if val is not None:
                    vals.append(val)
            if vals:
                metrics.setdefault(key,[]).extend(vals)
                raw.append({"metric_class":key,"column":col,"header":header[col],"values":vals})
    return metrics, raw

def extract_rowwise(rows):
    metrics={}
    raw=[]
    for r in rows:
        joined=' '.join(r)
        val=last_num(r)
        if val is None:
            continue
        for name in matching_keys(joined):
            metrics.setdefault(name,[]).append(val)
            raw.append({"metric_class":name,"row":r,"value":val})
    return metrics, raw

def extract(rows):
    metrics, raw = extract_columnar(rows)
    column_keys=set(metrics)
    row_metrics, row_raw = extract_rowwise(rows)
    for key, vals in row_metrics.items():
        if key not in metrics:
            metrics[key]=vals
    raw.extend(item for item in row_raw if item["metric_class"] not in column_keys)
    summary={k: (mean([x for x in v if x is not None]) if any(x is not None for x in v) else None) for k,v in metrics.items()}
    return summary, raw

def discover_kernel_candidates(rows):
    candidates=[]
    for r in rows:
        j=' '.join(r)
        if re.search(r'kernel|void|_Z|cuda', j, re.I):
            # Very loose extraction: keep rows that mention kernel-like names.
            candidates.append({"row": r})
    return candidates[:50]

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--input', required=True)
    ap.add_argument('--output-dir', required=True)
    ap.add_argument('--mode', default='metrics', choices=['metrics','discovery'])
    ns=ap.parse_args()
    out=Path(ns.output_dir); out.mkdir(parents=True, exist_ok=True)
    rows=parse_rows(Path(ns.input))
    summary, raw = extract(rows)
    (out/'metrics_summary.json').write_text(json.dumps(summary, indent=2), encoding='utf-8')
    (out/'metrics_extracted.jsonl').write_text('\n'.join(json.dumps(x, ensure_ascii=False) for x in raw)+'\n', encoding='utf-8')
    if ns.mode=='discovery':
        (out/'kernel_candidates.json').write_text(json.dumps(discover_kernel_candidates(rows), indent=2), encoding='utf-8')
    print(f"Wrote {out/'metrics_summary.json'}")
if __name__=='__main__': main()
