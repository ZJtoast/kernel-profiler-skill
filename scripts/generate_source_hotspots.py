#!/usr/bin/env python3
"""Generate standardized source_hotspots.csv from NCU source/raw text.
This is a tolerant extractor. If source correlation is unavailable, it emits a reason row.
"""
from __future__ import annotations
import argparse, csv, re
from pathlib import Path

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--input', required=True, help='NCU source page text/csv output')
    ap.add_argument('--output', required=True)
    ns=ap.parse_args()
    text=Path(ns.input).read_text(errors='replace') if Path(ns.input).exists() else ''
    rows=[]
    line_re=re.compile(r'(?P<file>[^\s:]+\.(?:cu|cuh|cpp|cc|c|h)):(?P<line>\d+)')
    sass_re=re.compile(r'\b(?P<op>LDG|STG|LDS|STS|ATOM|RED|BAR|HMMA|MMA|WGMMA|FFMA|FADD|FMUL|MUFU|IMAD|ISETP|BRA|CP\.ASYNC|TMA)\b', re.I)
    for raw in text.splitlines():
        lm=line_re.search(raw)
        sm=sass_re.search(raw)
        if lm or sm:
            rows.append({
                'source_file': lm.group('file') if lm else '',
                'line': lm.group('line') if lm else '',
                'function': '',
                'sass_opcode': sm.group('op').upper() if sm else '',
                'ptx_opcode': '',
                'metric': '',
                'value': '',
                'stall_reason': '',
                'bottleneck_class': '',
                'confidence': 'low' if not (lm and sm) else 'medium',
                'evidence': raw[:300]
            })
    if not rows:
        rows.append({'source_file':'','line':'','function':'','sass_opcode':'','ptx_opcode':'','metric':'','value':'','stall_reason':'','bottleneck_class':'source_mapping_unavailable','confidence':'low','evidence':'No source/SASS/PTX-correlated rows were detected. Rebuild with -lineinfo or export NCU source page.'})
    with open(ns.output,'w',newline='',encoding='utf-8') as f:
        w=csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader(); w.writerows(rows)
    print(f'Wrote {ns.output}')
if __name__=='__main__': main()
