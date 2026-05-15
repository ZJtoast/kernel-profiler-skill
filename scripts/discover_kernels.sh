#!/usr/bin/env bash
set -euo pipefail
# Low-cost NVIDIA Nsight Compute kernel discovery helper.
# Usage: discover_kernels.sh profile-target.yaml ./profile/<id>/details
TARGET_YAML=${1:-profile-target.yaml}
OUTDIR=${2:-./profile/discovery/details}
mkdir -p "$OUTDIR"
python3 - <<'PY' "$TARGET_YAML" "$OUTDIR"
import sys, yaml, shlex, pathlib, subprocess, json, os
cfg=yaml.safe_load(open(sys.argv[1], encoding='utf-8'))
out=pathlib.Path(sys.argv[2]); out.mkdir(parents=True, exist_ok=True)
t=cfg['target']; p=cfg.get('profiling',{}); priv=cfg.get('privilege',{})
cmd=[t['executable'], *map(str,t.get('args',[]))]
base=['ncu','--set','basic','--launch-count','1','--page','raw','--csv']
# Do not use full profile during discovery. Keep it cheap.
full=base+list(map(str,p.get('extra_profiler_options',[])))+cmd
prefix=[]
if priv.get('mode') == 'authorized_sudo':
    prefix=['sudo']
(pathlib.Path(out)/'00_discovery_command.sh').write_text(' '.join(map(shlex.quote,prefix+full))+'\n')
print(' '.join(map(shlex.quote,prefix+full)))
PY
# Execute after command is printed so commands can be inspected before collection.
bash "$OUTDIR/00_discovery_command.sh" > "$OUTDIR/00_discovery_raw.csv" 2> "$OUTDIR/00_discovery_stderr.txt" || true
python3 "$(dirname "$0")/extract_ncu_metrics.py" --input "$OUTDIR/00_discovery_raw.csv" --output-dir "$OUTDIR" --mode discovery || true
