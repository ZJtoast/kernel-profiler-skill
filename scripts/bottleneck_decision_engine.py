#!/usr/bin/env python3
"""Optional bottleneck decision engine.
Default mode is off. Run only when profile-target.yaml enables analysis.enable_bottleneck_decision_engine.
"""
from __future__ import annotations
import argparse, json, yaml, operator
from pathlib import Path
OPS={'>=':operator.ge,'>':operator.gt,'<=':operator.le,'<':operator.lt,'==':operator.eq}

def check_cond(metrics, cond):
    v=metrics.get(cond['metric'])
    if v is None: return False
    return OPS[cond['op']](float(v), float(cond['value']))

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--metrics', required=True)
    ap.add_argument('--rules', default='references/portable/rules/bottleneck_rules.yaml')
    ap.add_argument('--target', default=None)
    ap.add_argument('--output', required=True)
    ns=ap.parse_args()
    metrics=json.loads(Path(ns.metrics).read_text())
    rules=yaml.safe_load(Path(ns.rules).read_text())
    enabled=False
    if ns.target:
        target=yaml.safe_load(Path(ns.target).read_text())
        enabled=bool(target.get('analysis',{}).get('enable_bottleneck_decision_engine', False))
    if not enabled:
        result={"enabled":False,"message":"Decision engine disabled by default. Use profile-target.yaml analysis.enable_bottleneck_decision_engine=true to enable.","findings":[]}
    else:
        findings=[]
        for name,r in rules['rules'].items():
            all_ok=all(check_cond(metrics,c) for c in r.get('require_all',[]))
            any_list=r.get('require_any',[])
            any_ok=True if not any_list else any(check_cond(metrics,c) for c in any_list)
            if all_ok and any_ok:
                findings.append({"id":name,"severity":r.get('severity'),"evidence":r.get('evidence_text'),"next_actions":r.get('next_actions',[])})
        result={"enabled":True,"findings":findings,"metrics_used":metrics}
    Path(ns.output).write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps(result, indent=2))
if __name__=='__main__': main()
