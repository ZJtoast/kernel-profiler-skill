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
detected=ncu_bin
try:
    resolved=subprocess.check_output(['bash','-lc',f'command -v {shlex.quote(ncu_bin)} || true'], text=True).strip()
    if resolved:
        detected=resolved
    if '/' in detected or '/' in ncu_bin:
        real=subprocess.check_output(['bash','-lc',f'readlink -f {shlex.quote(detected)} 2>/dev/null || printf %s {shlex.quote(detected)}'], text=True).strip()
        if real:
            detected=real
except Exception:
    pass
base=[ncu_bin,'--set','basic','--launch-count','1','--page','raw','--csv']
# Do not use full profile during discovery. Keep it cheap.
full=base+list(map(str,p.get('extra_profiler_options',[])))+cmd
prefix=[]
if priv.get('mode') == 'full_sudo':
    prefix=['sudo','-n']
(pathlib.Path(out)/'00_discovery_command.sh').write_text(' '.join(map(shlex.quote,prefix+full))+'\n')
(pathlib.Path(out)/'00_discovery_ncu_path.txt').write_text(detected+'\n', encoding='utf-8')
print(f"[discovery] command written to {pathlib.Path(out)/'00_discovery_command.sh'}")
PY
# Execute after command is printed so commands can be inspected before collection.
set +e
bash "$OUTDIR/00_discovery_command.sh" > "$OUTDIR/00_discovery_raw.csv" 2> "$OUTDIR/00_discovery_stderr.txt"
status=$?
set -e
if [[ "$status" -ne 0 ]] && grep -Eqi "ERR_NVGPUCTRPERM|password is required|a password is required|permission|not permitted|Operation not permitted" "$OUTDIR/00_discovery_stderr.txt"; then
  NCU_PATH=$(cat "$OUTDIR/00_discovery_ncu_path.txt" 2>/dev/null || true)
  cat >&2 <<GUIDE

NCU discovery 需要 sudo 权限，但当前 agent 不能交互式输入 sudo 密码。
本次 profile 已停止。请先为 agent 已确认的当前 CUDA 环境 ncu 路径配置窄范围 NOPASSWD，然后在下一次对话中重新发起 profile。

agent 检测到的默认 ncu 绝对路径：

  ${NCU_PATH:-/absolute/path/to/active/cuda/bin/ncu}

步骤 1：创建 sudoers 规则。

  sudo visudo -f /etc/sudoers.d/kernel-profiler-ncu

写入一行，替换 USERNAME，并使用上面 agent 检测到的 ncu 绝对路径：

  USERNAME ALL=(root) NOPASSWD: ${NCU_PATH:-/absolute/path/to/selected/cuda/bin/ncu}

USERNAME 是 \`whoami\` 输出的登录用户名。不要写真实用户名到本 skill 的文件里。

步骤 2：验证：

  sudo -n ${NCU_PATH:-/absolute/path/to/selected/cuda/bin/ncu} --version
  sudo -n ncu --version
  sudo -n ${NCU_PATH:-/absolute/path/to/selected/cuda/bin/ncu} --list-sections

步骤 3：多 CUDA 环境必须固定同一个 ncu。后续 profile 前加载同一个 CUDA module / PATH，让 \`ncu\` 仍然解析到上面路径。

不要配置 NOPASSWD: ALL，也不要把 sudo 密码写入文件、命令、日志或 profile/sudokey。
本次 profile 已停止；配置完成后请在下一次对话中重新发起 profile。
GUIDE
  exit 77
fi
if [[ "$status" -ne 0 ]]; then
  cat "$OUTDIR/00_discovery_stderr.txt" >&2
fi
python3 "$(dirname "$0")/extract_ncu_metrics.py" --input "$OUTDIR/00_discovery_raw.csv" --output-dir "$OUTDIR" --mode discovery || true
