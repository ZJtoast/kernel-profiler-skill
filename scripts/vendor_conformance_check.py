#!/usr/bin/env python3
"""Minimal vendor backend conformance check.
It checks adapter metadata and required workflow capabilities. It does not execute a profiler.
"""
from __future__ import annotations
import argparse, yaml, sys
from pathlib import Path
REQUIRED_CAPABILITIES=[
    'can_discover_kernel','can_filter_kernel','can_collect_basic','can_collect_memory',
    'can_collect_compute','can_collect_occupancy','can_collect_roofline','can_export_raw_metrics',
    'can_link_source_or_isa','can_compare_reports',
    'can_profile_python_process','can_profile_triton_jit_kernels'
]

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--adapter', required=True)
    ns=ap.parse_args(); data=yaml.safe_load(Path(ns.adapter).read_text())
    caps=data.get('capabilities',{})
    missing=[c for c in REQUIRED_CAPABILITIES if not caps.get(c, False)]
    if missing:
        print('FAILED: missing capabilities: '+', '.join(missing)); sys.exit(1)
    print('PASSED: vendor adapter declares all required capabilities')
if __name__=='__main__': main()
