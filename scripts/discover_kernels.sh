#!/usr/bin/env bash
set -euo pipefail
# Low-cost NVIDIA Nsight Compute kernel discovery helper.
# Usage: discover_kernels.sh ./profile/<id>/profile-target.yaml ./profile/<id>/details
TARGET_YAML=${1:-./profile/profile-target.yaml}
OUTDIR=${2:-./profile/discovery/details}
mkdir -p "$OUTDIR"
python3 - <<'PY' "$TARGET_YAML" "$OUTDIR"
import sys, yaml, shlex, pathlib, subprocess, json, os
cfg=yaml.safe_load(open(sys.argv[1], encoding='utf-8'))
out=pathlib.Path(sys.argv[2]); out.mkdir(parents=True, exist_ok=True)
t=cfg['target']; p=cfg.get('profiling',{}); priv=cfg.get('privilege',{})
cmd=[t['executable'], *map(str,t.get('args',[]))]
default_sudo_ncu='/usr/local/cuda/bin/ncu'
ncu_path_file=pathlib.Path('profile')/'ncu_path'
def ensure_ncu_path_file():
    ncu_path_file.parent.mkdir(parents=True, exist_ok=True)
    if not ncu_path_file.exists():
        ncu_path_file.write_text(default_sudo_ncu + '\n', encoding='utf-8')
    value=''
    for line in ncu_path_file.read_text(encoding='utf-8', errors='replace').splitlines():
        if line.strip():
            value=line.strip()
            break
    if not value:
        value=default_sudo_ncu
        ncu_path_file.write_text(value + '\n', encoding='utf-8')
    return value

if priv.get('mode') == 'full_sudo':
    ncu_bin=ensure_ncu_path_file()
    detected=ncu_bin
else:
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
(pathlib.Path(out)/'00_discovery_ncu_path_file.txt').write_text(str(ncu_path_file)+'\n', encoding='utf-8')
print(f"[discovery] command written to {pathlib.Path(out)/'00_discovery_command.sh'}")
PY
# Execute after command is printed so commands can be inspected before collection.
DISCOVERY_ERR="$(mktemp)"
set +e
bash "$OUTDIR/00_discovery_command.sh" > "$OUTDIR/00_discovery_raw.csv" 2> "$DISCOVERY_ERR"
status=$?
set -e

if [[ "$status" -ne 0 ]] && grep -Eqi "No kernels? (were )?profiled|No kernels? matched|No matching kernels?|No kernels? selected|No launches? (were )?profiled|No profiled kernels?|No kernels? found" "$DISCOVERY_ERR" "$OUTDIR/00_discovery_raw.csv" 2>/dev/null; then
  rm -f "$DISCOVERY_ERR" "$OUTDIR/00_discovery_raw.csv"
  cat >&2 <<MISS
[discovery] stopped: target command launched no profiled GPU kernel.

Profile 已停止。请检查目标命令是否真的执行 CUDA kernel、launch skip/count 是否过大，或先提供更准确的 kernel 名称/filter。
MISS
  exit 78
fi

if [[ "$status" -ne 0 ]] && { grep -Eqi "ERR_NVGPUCTRPERM|password is required|a password is required|sudo:.*password|Operation not permitted|not permitted|permission denied" "$DISCOVERY_ERR" 2>/dev/null || { grep -q '^sudo -n ' "$OUTDIR/00_discovery_command.sh" && grep -Eqi "No such file|command not found|not found" "$DISCOVERY_ERR" 2>/dev/null; }; }; then
  NCU_PATH=$(cat "$OUTDIR/00_discovery_ncu_path.txt" 2>/dev/null || true)
  NCU_PATH_FILE=$(cat "$OUTDIR/00_discovery_ncu_path_file.txt" 2>/dev/null || echo "./profile/ncu_path")
  cat >&2 <<GUIDE

NCU discovery 需要 sudo 权限，但当前 agent 不能交互式输入 sudo 密码。
本次 profile 已停止。请先选择一个 ncu 绝对路径，配置窄范围 NOPASSWD，并把该路径写入 ${NCU_PATH_FILE:-./profile/ncu_path}。

当前 ${NCU_PATH_FILE:-./profile/ncu_path} 内容：

  ${NCU_PATH:-/usr/local/cuda/bin/ncu}

步骤 1：在你准备 profile 的 CUDA 环境中运行：

  command -v ncu
  readlink -f "\$(command -v ncu)"

从输出中选择你要固定使用的 ncu 路径，例如：

  /usr/local/cuda-12.9/bin/ncu

步骤 2：创建 sudoers 规则。

  sudo visudo -f /etc/sudoers.d/kernel-profiler-ncu

写入一行，替换 USERNAME 和你选择的 ncu 绝对路径：

  USERNAME ALL=(root) NOPASSWD: /usr/local/cuda-12.9/bin/ncu

USERNAME 是 \`whoami\` 输出的登录用户名。不要写真实用户名到本 skill 的文件里。

步骤 3：把同一个路径写入 ${NCU_PATH_FILE:-./profile/ncu_path}。

  mkdir -p ./profile
  printf '%s\n' '/usr/local/cuda-12.9/bin/ncu' > "${NCU_PATH_FILE:-./profile/ncu_path}"

步骤 4：验证：

  sudo -n "\$(cat "${NCU_PATH_FILE:-./profile/ncu_path}")" --version
  sudo -n "\$(cat "${NCU_PATH_FILE:-./profile/ncu_path}")" --list-sections

不要配置 NOPASSWD: ALL，也不要把 sudo 密码写入文件、命令、日志或 profile/sudokey。
本次 profile 已停止；配置完成后请在下一次对话中重新发起 profile。
GUIDE
  rm -f "$DISCOVERY_ERR" "$OUTDIR/00_discovery_raw.csv"
  exit 77
fi
if [[ "$status" -ne 0 ]]; then
  cat "$DISCOVERY_ERR" >&2
  rm -f "$DISCOVERY_ERR"
  exit "$status"
fi
rm -f "$DISCOVERY_ERR"
if grep -Eqi "No kernels? (were )?profiled|No kernels? matched|No matching kernels?|No kernels? selected|No launches? (were )?profiled|No profiled kernels?|No kernels? found" "$OUTDIR/00_discovery_raw.csv" 2>/dev/null; then
  rm -f "$OUTDIR/00_discovery_raw.csv"
  cat >&2 <<MISS
[discovery] stopped: target command launched no profiled GPU kernel.

Profile 已停止。请检查目标命令是否真的执行 CUDA kernel、launch skip/count 是否过大，或先提供更准确的 kernel 名称/filter。
MISS
  exit 78
fi
python3 "$(dirname "$0")/extract_ncu_metrics.py" --input "$OUTDIR/00_discovery_raw.csv" --output-dir "$OUTDIR" --mode discovery >/dev/null 2>&1 || true
