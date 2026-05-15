#!/usr/bin/env python3
"""Generate before/after regression report with concrete data and noise tolerance.

Baseline resolution order for --baseline auto:
1. Same kernel directory's latest previous sibling under output_root.
2. Most recent profile directory with matching kernel name prefix.
3. Abort with clear message; never guess across unrelated kernels.
"""
from __future__ import annotations
import argparse, json, os, re, sys
from pathlib import Path
from datetime import datetime

LOWER_IS_BETTER={'duration'}
HIGHER_IS_BETTER={'sm_throughput_pct','memory_throughput_pct','dram_throughput_pct','achieved_occupancy_pct','theoretical_occupancy_pct','l2_hit_rate_pct','l1tex_hit_rate_pct','ipc'}

def load_metrics(profile_dir: Path):
    candidates=[profile_dir/'details'/'metrics_summary.json', profile_dir/'metrics_summary.json']
    for c in candidates:
        if c.exists(): return json.loads(c.read_text())
    raise FileNotFoundError(f'No metrics_summary.json found in {profile_dir}')

def kernel_prefix(name):
    return re.sub(r'_\d{8}_\d{6}$','',name)

def resolve_auto(current: Path):
    root=current.parent
    pref=kernel_prefix(current.name)
    candidates=[]
    for p in root.iterdir() if root.exists() else []:
        if p.is_dir() and p != current and kernel_prefix(p.name)==pref:
            try: mtime=p.stat().st_mtime
            except Exception: continue
            if mtime < current.stat().st_mtime:
                candidates.append((mtime,p))
    if not candidates:
        return None
    return sorted(candidates)[-1][1]

def classify(metric, before, after, tol):
    if before is None or after is None: return 'insufficient_data'
    if before == 0: return 'insufficient_data'
    pct=(after-before)/abs(before)*100.0
    if abs(pct) <= tol: return 'normal_variation'
    if metric in LOWER_IS_BETTER:
        return 'improved' if pct < -tol else 'regressed'
    if metric in HIGHER_IS_BETTER:
        return 'improved' if pct > tol else 'regressed'
    return 'changed'

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--current', required=True)
    ap.add_argument('--baseline', default='auto')
    ap.add_argument('--tolerance-pct', type=float, default=2.0)
    ap.add_argument('--output', required=True)
    ns=ap.parse_args()
    cur=Path(ns.current)
    base=resolve_auto(cur) if ns.baseline=='auto' else Path(ns.baseline)
    if base is None:
        msg='No valid previous baseline found for the same kernel prefix. Provide --baseline explicitly.'
        Path(ns.output).write_text('# Kernel Profile Regression Report\n\n'+msg+'\n', encoding='utf-8')
        print(msg, file=sys.stderr); sys.exit(2)
    bm=load_metrics(base); cm=load_metrics(cur)
    keys=sorted(set(bm)|set(cm))
    rows=[]; verdicts=[]
    for k in keys:
        b=bm.get(k); a=cm.get(k)
        if not isinstance(b,(int,float)) or not isinstance(a,(int,float)): continue
        delta=a-b; pct=(delta/abs(b)*100.0) if b else None
        verdict=classify(k,b,a,ns.tolerance_pct)
        verdicts.append(verdict)
        rows.append((k,b,a,delta,pct,verdict))
    regressions=verdicts.count('regressed'); improvements=verdicts.count('improved')
    overall='REGRESSION' if regressions>0 and regressions>=improvements else ('IMPROVEMENT' if improvements>0 else 'NO MATERIAL CHANGE')
    md=['# Kernel Profile Regression Report','',f'- Current: `{cur}`',f'- Baseline: `{base}`',f'- Noise tolerance: ±{ns.tolerance_pct:.2f}%','',f'## Overall Verdict: {overall}','', '| Metric | Baseline | Current | Delta | Delta % | Judgment |','|---|---:|---:|---:|---:|---|']
    for k,b,a,d,p,v in rows:
        md.append(f'| `{k}` | {b:.6g} | {a:.6g} | {d:.6g} | {p:.3f}% | {v} |')
    md += ['','## Interpretation Rules','', '- Changes within the configured tolerance are classified as normal random variation.', '- Duration is lower-is-better; throughput, occupancy, cache-hit, and IPC metrics are higher-is-better.', '- A regression verdict requires a metric to exceed the tolerance in the unfavorable direction.', '- The report does not claim causal optimization reasons unless source hotspot and bottleneck evidence also changed.']
    Path(ns.output).write_text('\n'.join(md)+'\n', encoding='utf-8')
    print(f'Wrote {ns.output}; baseline={base}; verdict={overall}')
if __name__=='__main__': main()
