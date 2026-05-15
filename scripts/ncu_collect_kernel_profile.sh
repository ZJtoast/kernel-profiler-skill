#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  ncu_collect_kernel_profile.sh --target-cmd "./app arg1" --kernel-regex ".*kernel.*" [options]

Options:
  --output-dir DIR          Output directory. Default: ./profile/kernel_profile
  --kernel-name NAME        Human-readable kernel name. Default: target_kernel
  --launch-skip N           Matching launches to skip. Default: 10
  --launch-count N          Matching launches to profile. Default: 1
  --devices ID              Optional ncu --devices value.
  --ncu-bin CMD             Nsight Compute CLI command. Default: $NCU_BIN or ncu.
                            Default profiling keeps using "ncu" from the active CUDA environment.
  --full                    Also run --set full as details/08_full.
  --no-source               Skip source/SASS collection.
  --extra "ARGS"            Extra raw ncu options appended before target command.
  --runtime NAME           Target runtime label: native | python | python-triton. Default: native.
  --nvtx-range NAME        Add Nsight Compute NVTX include filter for a named range.
  --sudo                  Run ncu through non-interactive sudo (-n) when not already root.
                          Requires root or narrow NOPASSWD for the detected ncu path.
  --stages LIST            Comma-separated stages to run. Default: auto.
                           Names: auto,all,basic,speed-of-light,memory,compute,occupancy,roofline,source,full.
USAGE
}

print_nopasswd_guide() {
  local ncu_cmd="${1:-ncu}"
  local ncu_path="${2:-}"
  if [[ -z "$ncu_path" ]]; then
    ncu_path="/absolute/path/to/active/cuda/bin/ncu"
  fi
  cat <<GUIDE

NCU 需要 sudo 权限，但当前 agent 不能交互式输入 sudo 密码。
本次 profile 已停止。请先为 agent 已确认的当前 CUDA 环境 ncu 路径配置窄范围 NOPASSWD，然后在下一次对话中重新发起 profile。

agent 当前使用的 ncu 命令：

  $ncu_cmd

agent 检测到的默认 ncu 绝对路径：

  $ncu_path

步骤 1：创建 sudoers 规则。

  sudo visudo -f /etc/sudoers.d/kernel-profiler-ncu

写入一行，替换 USERNAME，并使用上面 agent 检测到的 ncu 绝对路径：

  USERNAME ALL=(root) NOPASSWD: $ncu_path

USERNAME 是 \`whoami\` 输出的登录用户名。不要写真实用户名到本 skill 的文件里。

步骤 2：验证免密是否成功。

  sudo -n $ncu_path --version
  sudo -n ncu --version
  sudo -n $ncu_path --list-sections

步骤 3：多 CUDA 环境必须固定同一个 ncu。

后续 profile 前加载同一个 CUDA module / PATH，让 \`ncu\` 仍然解析到：

  $ncu_path

正常情况下脚本会继续直接执行 \`ncu\`，不需要在每个 profile 命令里写绝对路径。
只有当服务器的 sudo secure_path 导致 \`sudo -n ncu\` 无法解析时，才临时使用：

  scripts/ncu_collect_kernel_profile.sh --ncu-bin "$ncu_path" --sudo ...

不要配置 NOPASSWD: ALL，也不要把 sudo 密码写入文件、命令、日志或 profile/sudokey。
本次 profile 已停止；配置完成后请在下一次对话中重新发起 profile。
GUIDE
}

TARGET_CMD=""
KERNEL_REGEX=""
KERNEL_NAME="target_kernel"
OUTPUT_DIR="./profile/kernel_profile"
LAUNCH_SKIP="10"
LAUNCH_COUNT="1"
DEVICES=""
NCU_BIN="${NCU_BIN:-ncu}"
RUN_FULL="0"
RUN_SOURCE="1"
EXTRA=""
RUNTIME="native"
NVTX_RANGE=""
USE_SUDO="0"
STAGES="auto"
SUDO_PREFIX=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target-cmd) TARGET_CMD="$2"; shift 2 ;;
    --kernel-regex) KERNEL_REGEX="$2"; shift 2 ;;
    --kernel-name) KERNEL_NAME="$2"; shift 2 ;;
    --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
    --launch-skip) LAUNCH_SKIP="$2"; shift 2 ;;
    --launch-count) LAUNCH_COUNT="$2"; shift 2 ;;
    --devices) DEVICES="$2"; shift 2 ;;
    --ncu-bin) NCU_BIN="$2"; shift 2 ;;
    --full) RUN_FULL="1"; shift ;;
    --no-source) RUN_SOURCE="0"; shift ;;
    --extra) EXTRA="$2"; shift 2 ;;
    --runtime) RUNTIME="$2"; shift 2 ;;
    --nvtx-range) NVTX_RANGE="$2"; shift 2 ;;
    --sudo) USE_SUDO="1"; shift ;;
    --stages) STAGES="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$TARGET_CMD" || -z "$KERNEL_REGEX" ]]; then
  usage >&2
  exit 2
fi

STAGE_AUTO="0"
STAGE_ALL="0"
STAGE_BASIC="0"
STAGE_SPEED="0"
STAGE_MEMORY="0"
STAGE_COMPUTE="0"
STAGE_OCCUPANCY="0"
STAGE_ROOFLINE="0"
STAGE_SOURCE="0"
STAGE_FULL="0"

IFS=',' read -ra STAGE_ITEMS <<< "$STAGES"
for stage in "${STAGE_ITEMS[@]}"; do
  stage="$(echo "$stage" | tr '[:upper:]' '[:lower:]' | tr '_' '-' | xargs)"
  case "$stage" in
    auto|evidence|targeted)
      STAGE_AUTO="1"
      ;;
    all)
      STAGE_ALL="1"
      ;;
    basic)
      STAGE_BASIC="1"
      ;;
    speed|speed-of-light|speedoflight|sol)
      STAGE_SPEED="1"
      ;;
    memory|mem)
      STAGE_MEMORY="1"
      ;;
    compute)
      STAGE_COMPUTE="1"
      ;;
    occupancy|launch|launch-occupancy|scheduler)
      STAGE_OCCUPANCY="1"
      ;;
    roofline)
      STAGE_ROOFLINE="1"
      ;;
    source|sass|ptx)
      STAGE_SOURCE="1"
      ;;
    full)
      STAGE_FULL="1"
      ;;
    "")
      ;;
    *)
      echo "Unknown stage in --stages: $stage" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$STAGE_ALL" == "1" ]]; then
  STAGE_AUTO="0"
  STAGE_BASIC="1"
  STAGE_SPEED="1"
  STAGE_MEMORY="1"
  STAGE_COMPUTE="1"
  STAGE_OCCUPANCY="1"
  STAGE_ROOFLINE="1"
  STAGE_SOURCE="1"
fi

if [[ "$STAGE_AUTO" == "1" ]]; then
  STAGE_BASIC="1"
fi

if [[ "$RUN_FULL" == "1" ]]; then
  STAGE_FULL="1"
fi

resolve_ncu_path_for_guide() {
  local cmd="$1"
  local found="$cmd"
  if command -v "$cmd" >/dev/null 2>&1; then
    found="$(command -v "$cmd")"
  fi
  if [[ "$found" != */* && "$cmd" != */* ]]; then
    echo "$found"
    return
  fi
  if command -v readlink >/dev/null 2>&1; then
    readlink -f "$found" 2>/dev/null || echo "$found"
  else
    echo "$found"
  fi
}

NCU_DETECTED_PATH="$(resolve_ncu_path_for_guide "$NCU_BIN")"

if [[ "$USE_SUDO" == "1" && "${EUID:-$(id -u)}" != "0" ]]; then
  SUDO_PREFIX=(sudo -n)
fi

if [[ "${#SUDO_PREFIX[@]}" -gt 0 ]]; then
  tmp_err="$(mktemp)"
  set +e
  "${SUDO_PREFIX[@]}" "$NCU_BIN" --version >/dev/null 2>"$tmp_err"
  sudo_status=$?
  set -e
  if [[ "$sudo_status" -ne 0 ]]; then
    if grep -Eqi "password is required|a password is required|permission|not permitted|Operation not permitted" "$tmp_err"; then
      print_nopasswd_guide "$NCU_BIN" "$NCU_DETECTED_PATH" >&2
      rm -f "$tmp_err"
      exit 77
    fi
    cat "$tmp_err" >&2
    rm -f "$tmp_err"
    exit "$sudo_status"
  fi
  rm -f "$tmp_err"
fi

mkdir -p "$OUTPUT_DIR/details" "$OUTPUT_DIR/visual"
COMMANDS="$OUTPUT_DIR/commands.sh"
ENVFILE="$OUTPUT_DIR/details/00_environment.txt"
touch "$COMMANDS"
chmod +x "$COMMANDS"

{
  echo "created_at: $(date -Iseconds)"
  echo "kernel_name: $KERNEL_NAME"
  echo "kernel_regex: $KERNEL_REGEX"
  echo "launch_skip: $LAUNCH_SKIP"
  echo "launch_count: $LAUNCH_COUNT"
  echo "target_cmd: $TARGET_CMD"
  echo "runtime: $RUNTIME"
  echo "stages: $STAGES"
  echo "ncu_command: $NCU_BIN"
  echo "ncu_detected_path: $NCU_DETECTED_PATH"
  if [[ -n "$NVTX_RANGE" ]]; then echo "nvtx_range: $NVTX_RANGE"; fi
  echo
  echo "## ncu version"
  "${SUDO_PREFIX[@]}" "$NCU_BIN" --version || true
  echo
  echo "## nvidia-smi"
  nvidia-smi || true
} > "$ENVFILE" 2>&1

FILTER=(--kernel-name-base demangled --kernel-name "regex:${KERNEL_REGEX}")
if [[ -n "$NVTX_RANGE" ]]; then
  FILTER+=(--nvtx --nvtx-include "${NVTX_RANGE}/")
fi
WINDOW=(--launch-skip "$LAUNCH_SKIP" --launch-count "$LAUNCH_COUNT")
DEVICE_ARGS=()
if [[ -n "$DEVICES" ]]; then
  DEVICE_ARGS=(--devices "$DEVICES")
fi

COLLECTED_STAGES=()

run_ncu_output() {
  local label="$1"; shift
  local output_name="$1"; shift
  local output_file="$OUTPUT_DIR/details/$output_name"
  local stderr_file="${output_file%.*}_stderr.txt"

  {
    printf '%q ' "${SUDO_PREFIX[@]}" "$NCU_BIN" "${DEVICE_ARGS[@]}" "$@" "${FILTER[@]}" "${WINDOW[@]}"
    if [[ -n "$EXTRA" ]]; then printf '%s ' "$EXTRA"; fi
    printf '%s > %q 2> %q\n' "$TARGET_CMD" "$output_file" "$stderr_file"
  } >> "$COMMANDS"

  echo "[profile] $label -> details/$output_name"
  # shellcheck disable=SC2086
  set +e
  "${SUDO_PREFIX[@]}" "$NCU_BIN" "${DEVICE_ARGS[@]}" "$@" "${FILTER[@]}" "${WINDOW[@]}" $EXTRA $TARGET_CMD > "$output_file" 2> "$stderr_file"
  local status=$?
  set -e
  if [[ "$status" -ne 0 ]]; then
    if grep -Eqi "ERR_NVGPUCTRPERM|password is required|a password is required|permission|not permitted|Operation not permitted" "$stderr_file"; then
      print_nopasswd_guide "$NCU_BIN" "$NCU_DETECTED_PATH" >&2
    else
      echo "[profile] $label failed; see details/$(basename "$stderr_file")" >&2
    fi
    return "$status"
  fi
  if [[ ! -s "$output_file" ]]; then
    echo "[profile] warning: $label produced an empty output file" >&2
  fi
  COLLECTED_STAGES+=("$label")
}

refresh_metrics() {
  cat "$OUTPUT_DIR"/details/*_raw.csv > "$OUTPUT_DIR/details/metrics_raw.csv" 2>/dev/null || true
  if [[ -s "$OUTPUT_DIR/details/metrics_raw.csv" ]]; then
    python3 "$(dirname "$0")/extract_ncu_metrics.py" \
      --input "$OUTPUT_DIR/details/metrics_raw.csv" \
      --output-dir "$OUTPUT_DIR/details" \
      > "$OUTPUT_DIR/details/extract_metrics_stdout.txt" \
      2> "$OUTPUT_DIR/details/extract_metrics_stderr.txt" || true
  fi
}

choose_auto_stage() {
  python3 - "$OUTPUT_DIR/details/metrics_summary.json" <<'PY'
import json, math, sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    metrics = json.loads(path.read_text(encoding="utf-8"))
except Exception:
    metrics = {}

def val(*keys):
    for key in keys:
        raw = metrics.get(key)
        try:
            num = float(raw)
        except (TypeError, ValueError):
            continue
        if not math.isnan(num):
            return num
    return None

sm = val("sm_throughput_pct")
mem = val("memory_throughput_pct", "dram_throughput_pct")
occ = val("achieved_occupancy_pct")
theo = val("theoretical_occupancy_pct")
ipc = val("ipc")

stage = "speed-of-light"
reason = "basic metrics do not yet expose a clear memory/compute/occupancy direction"

if occ is not None and occ < 45:
    stage = "occupancy"
    reason = f"achieved occupancy is low ({occ:.1f}%)"
elif occ is not None and theo is not None and theo - occ >= 20:
    stage = "occupancy"
    reason = f"achieved occupancy trails theoretical occupancy by {theo - occ:.1f} points"
elif mem is not None and (mem >= 65 or (sm is not None and mem - sm >= 10)):
    stage = "memory"
    reason = f"memory-side utilization dominates (memory={mem:.1f}%, sm={sm if sm is not None else float('nan'):.1f}%)"
elif sm is not None and (sm >= 65 or (mem is not None and sm - mem >= 10)):
    stage = "compute"
    reason = f"SM utilization dominates (sm={sm:.1f}%, memory={mem if mem is not None else float('nan'):.1f}%)"
elif sm is not None and mem is not None and sm < 35 and mem < 35:
    stage = "occupancy"
    reason = f"both SM and memory utilization are low (sm={sm:.1f}%, memory={mem:.1f}%)"
elif ipc is not None and ipc < 1.0:
    stage = "occupancy"
    reason = f"IPC is low ({ipc:.2f}); scheduler/warp-state evidence is needed"
elif mem is not None or sm is not None:
    stage = "memory" if (mem or 0) >= (sm or 0) else "compute"
    reason = "selected the dominant utilization side from basic metrics"

print(stage + "|" + reason)
PY
}

run_stage_by_name() {
  local stage="$1"
  case "$stage" in
    basic)
      run_ncu_output "basic" "01_basic_raw.csv" --set basic --page raw --csv
      ;;
    speed-of-light)
      run_ncu_output "speed_of_light" "02_speed_of_light_raw.csv" --section SpeedOfLight --page raw --csv
      ;;
    memory)
      run_ncu_output "memory" "03_memory_raw.csv" --section MemoryWorkloadAnalysis --section SourceCounters --page raw --csv
      ;;
    compute)
      run_ncu_output "compute" "04_compute_raw.csv" --section ComputeWorkloadAnalysis --section InstructionStats --section SourceCounters --page raw --csv
      ;;
    occupancy)
      run_ncu_output "occupancy" "05_occupancy_launch_raw.csv" --section LaunchStats --section Occupancy --section SchedulerStats --section WarpStateStats --page raw --csv
      ;;
    roofline)
      local sections_file="$OUTPUT_DIR/details/06_roofline_sections.txt"
      local sections_err="$OUTPUT_DIR/details/06_roofline_sections_stderr.txt"
      if "${SUDO_PREFIX[@]}" "$NCU_BIN" --list-sections > "$sections_file" 2> "$sections_err" && grep -qi "SpeedOfLight_RooflineChart" "$sections_file"; then
        run_ncu_output "roofline" "06_roofline_raw.csv" --section SpeedOfLight_RooflineChart --page raw --csv
      else
        echo "Roofline section not found for current ncu; see details/06_roofline_sections.txt." > "$OUTPUT_DIR/details/06_roofline_missing.txt"
        echo "[profile] roofline skipped; section not found"
      fi
      ;;
    source)
      if [[ "$RUN_SOURCE" == "1" ]]; then
        run_ncu_output "source" "07_source_raw.csv" --section SourceCounters --page source --print-source sass --csv
      fi
      ;;
    full)
      run_ncu_output "full" "08_full_raw.csv" --set full --page raw --csv
      ;;
  esac
}

if [[ "$STAGE_AUTO" == "1" ]]; then
  run_stage_by_name basic
  refresh_metrics
  auto_decision="$(choose_auto_stage)"
  auto_stage="${auto_decision%%|*}"
  auto_reason="${auto_decision#*|}"
  echo "[profile] auto selected: $auto_stage - $auto_reason"
  if [[ "$auto_stage" != "basic" ]]; then
    run_stage_by_name "$auto_stage"
    refresh_metrics
  fi
  if [[ "$STAGE_SPEED" == "1" && "$auto_stage" != "speed-of-light" ]]; then run_stage_by_name speed-of-light; refresh_metrics; fi
  if [[ "$STAGE_MEMORY" == "1" && "$auto_stage" != "memory" ]]; then run_stage_by_name memory; refresh_metrics; fi
  if [[ "$STAGE_COMPUTE" == "1" && "$auto_stage" != "compute" ]]; then run_stage_by_name compute; refresh_metrics; fi
  if [[ "$STAGE_OCCUPANCY" == "1" && "$auto_stage" != "occupancy" ]]; then run_stage_by_name occupancy; refresh_metrics; fi
  if [[ "$STAGE_ROOFLINE" == "1" && "$auto_stage" != "roofline" ]]; then run_stage_by_name roofline; refresh_metrics; fi
  if [[ "$STAGE_SOURCE" == "1" && "$auto_stage" != "source" ]]; then run_stage_by_name source; refresh_metrics; fi
  if [[ "$STAGE_FULL" == "1" ]]; then
    run_stage_by_name full
    refresh_metrics
  fi
else
  if [[ "$STAGE_BASIC" == "1" ]]; then run_stage_by_name basic; fi
  if [[ "$STAGE_SPEED" == "1" ]]; then run_stage_by_name speed-of-light; fi
  if [[ "$STAGE_MEMORY" == "1" ]]; then run_stage_by_name memory; fi
  if [[ "$STAGE_COMPUTE" == "1" ]]; then run_stage_by_name compute; fi
  if [[ "$STAGE_OCCUPANCY" == "1" ]]; then run_stage_by_name occupancy; fi
  if [[ "$STAGE_ROOFLINE" == "1" ]]; then run_stage_by_name roofline; fi
  if [[ "$STAGE_SOURCE" == "1" ]]; then run_stage_by_name source; fi
  if [[ "$STAGE_FULL" == "1" ]]; then run_stage_by_name full; fi
  refresh_metrics
fi

if [[ -f "$OUTPUT_DIR/details/07_source_raw.csv" ]]; then
  python3 "$(dirname "$0")/generate_source_hotspots.py" \
    --input "$OUTPUT_DIR/details/07_source_raw.csv" \
    --output "$OUTPUT_DIR/details/source_hotspots.csv" \
    > "$OUTPUT_DIR/details/source_hotspots_stdout.txt" \
    2> "$OUTPUT_DIR/details/source_hotspots_stderr.txt" || true
elif [[ ! -f "$OUTPUT_DIR/details/source_hotspots.csv" ]]; then
  python3 "$(dirname "$0")/generate_source_hotspots.py" \
    --input /dev/null \
    --output "$OUTPUT_DIR/details/source_hotspots.csv" \
    > "$OUTPUT_DIR/details/source_hotspots_stdout.txt" \
    2> "$OUTPUT_DIR/details/source_hotspots_stderr.txt" || true
fi

cat > "$OUTPUT_DIR/run_manifest.yaml" <<MANIFEST
profile_id: "$(basename "$OUTPUT_DIR")"
created_at: "$(date -Iseconds)"
backend: "nvidia-ncu"
ncu_command: "$NCU_BIN"
ncu_detected_path: "$NCU_DETECTED_PATH"
runtime: "$RUNTIME"
privilege:
  sudo_requested: "$USE_SUDO"
  effective_uid: "${EUID:-$(id -u)}"
  password_stored: false
target_command: "$TARGET_CMD"
kernel:
  name: "$KERNEL_NAME"
  filter_mode: "regex"
  filter: "$KERNEL_REGEX"
  nvtx_range: "$NVTX_RANGE"
profiling:
  warmup_skip: $LAUNCH_SKIP
  launch_count: $LAUNCH_COUNT
  stages_requested: "$STAGES"
  stages_collected: "$(IFS=,; echo "${COLLECTED_STAGES[*]:-}")"
reports_directory: "details"
MANIFEST

if [[ ! -f "$OUTPUT_DIR/final_report.md" ]]; then
  cat > "$OUTPUT_DIR/final_report.md" <<REPORT
# Kernel Profile Report: $KERNEL_NAME

This placeholder was generated by ncu_collect_kernel_profile.sh.
Fill it using assets/templates/final_report_template.md and the reports in details/.

- Backend: nvidia-ncu
- Runtime: $RUNTIME
- Kernel filter: regex:$KERNEL_REGEX
- Launch window: skip=$LAUNCH_SKIP, count=$LAUNCH_COUNT
- Target: $TARGET_CMD
REPORT
fi

echo "Profile artifacts written to: $OUTPUT_DIR"
