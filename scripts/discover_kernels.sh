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
ncu_bin=str(p.get('ncu_bin') or 'ncu')
try:
    resolved=subprocess.check_output(['bash','-lc',f'command -v {shlex.quote(ncu_bin)} || true'], text=True).strip()
    if resolved:
        ncu_bin=resolved
    real=subprocess.check_output(['bash','-lc',f'readlink -f {shlex.quote(ncu_bin)} 2>/dev/null || printf %s {shlex.quote(ncu_bin)}'], text=True).strip()
    if real:
        ncu_bin=real
except Exception:
    pass
base=[ncu_bin,'--set','basic','--launch-count','1','--page','raw','--csv']
# Do not use full profile during discovery. Keep it cheap.
full=base+list(map(str,p.get('extra_profiler_options',[])))+cmd
prefix=[]
if priv.get('mode') == 'full_sudo':
    prefix=['sudo','-n']
(pathlib.Path(out)/'00_discovery_command.sh').write_text(' '.join(map(shlex.quote,prefix+full))+'\n')
print(' '.join(map(shlex.quote,prefix+full)))
PY
# Execute after command is printed so commands can be inspected before collection.
bash "$OUTDIR/00_discovery_command.sh" > "$OUTDIR/00_discovery_raw.csv" 2> "$OUTDIR/00_discovery_stderr.txt" || true
if grep -Eqi "ERR_NVGPUCTRPERM|password is required|a password is required|permission|not permitted|Operation not permitted" "$OUTDIR/00_discovery_stderr.txt"; then
  NCU_PATH=$(awk '{for (i=1; i<=NF; i++) if ($i ~ /(^|\/)ncu$/) {print $i; exit}}' "$OUTDIR/00_discovery_command.sh")
  cat >&2 <<GUIDE

Nsight Compute discovery needs privileged counters, but this agent cannot interactively type sudo passwords.
Configure exact-path NOPASSWD for the CUDA environment you want this profile to use:

  which ncu
  readlink -f \$(which ncu)
  sudo visudo -f /etc/sudoers.d/kernel-profiler-ncu

Add one line, replacing USERNAME and the path with the exact output above:

  USERNAME ALL=(root) NOPASSWD: ${NCU_PATH:-/absolute/path/to/selected/cuda/bin/ncu}

Then run discovery/profile with the same ncu path through profiling.ncu_bin or --ncu-bin.
GUIDE
fi
python3 "$(dirname "$0")/extract_ncu_metrics.py" --input "$OUTDIR/00_discovery_raw.csv" --output-dir "$OUTDIR" --mode discovery || true
