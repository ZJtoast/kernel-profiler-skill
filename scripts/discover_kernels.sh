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
set +e
bash "$OUTDIR/00_discovery_command.sh" > "$OUTDIR/00_discovery_raw.csv" 2> "$OUTDIR/00_discovery_stderr.txt"
status=$?
set -e
if [[ "$status" -ne 0 ]] && grep -Eqi "ERR_NVGPUCTRPERM|password is required|a password is required|permission|not permitted|Operation not permitted" "$OUTDIR/00_discovery_stderr.txt"; then
  NCU_PATH=$(awk '{for (i=1; i<=NF; i++) if ($i ~ /(^|\/)ncu$/) {print $i; exit}}' "$OUTDIR/00_discovery_command.sh")
  cat >&2 <<GUIDE

NCU discovery 需要 sudo 权限，但当前 agent 不能交互式输入 sudo 密码。
请先为当前 CUDA 环境中的精确 ncu 路径配置 NOPASSWD，然后在下一次对话中重新发起 profile。

步骤 1：在你要 profile 的 CUDA 环境中找到 ncu。

  which ncu
  readlink -f \$(which ncu)

步骤 2：创建 sudoers 规则。

  sudo visudo -f /etc/sudoers.d/kernel-profiler-ncu

写入一行，替换 USERNAME 和 ncu 路径：

  USERNAME ALL=(root) NOPASSWD: ${NCU_PATH:-/absolute/path/to/selected/cuda/bin/ncu}

步骤 3：验证：

  sudo -n ${NCU_PATH:-/absolute/path/to/selected/cuda/bin/ncu} --version
  sudo -n ${NCU_PATH:-/absolute/path/to/selected/cuda/bin/ncu} --list-sections

步骤 4：多 CUDA 环境必须固定同一个 ncu。后续通过 profiling.ncu_bin 或 --ncu-bin 使用同一路径。

不要配置 NOPASSWD: ALL，也不要把 sudo 密码写入文件、命令、日志或 profile/sudokey。
本次 profile 已停止；配置完成后请在下一次对话中重新发起 profile。
GUIDE
  exit 77
fi
if [[ "$status" -ne 0 ]]; then
  cat "$OUTDIR/00_discovery_stderr.txt" >&2
fi
python3 "$(dirname "$0")/extract_ncu_metrics.py" --input "$OUTDIR/00_discovery_raw.csv" --output-dir "$OUTDIR" --mode discovery || true
