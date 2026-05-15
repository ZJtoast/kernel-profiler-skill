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
  --ncu-bin PATH            Nsight Compute CLI path. Default: $NCU_BIN or ncu.
                            Use the exact CUDA environment path that has NOPASSWD.
  --full                    Also run --set full as details/08_full.
  --no-source               Skip source/SASS collection.
  --extra "ARGS"            Extra raw ncu options appended before target command.
  --runtime NAME           Target runtime label: native | python | python-triton. Default: native.
  --nvtx-range NAME        Add Nsight Compute NVTX include filter for a named range.
  --sudo                  Run ncu through non-interactive sudo (-n) when not already root.
                          Requires root or exact-path NOPASSWD; never accepts passwords.
  --stages LIST            Comma-separated stages to run. Default: all.
                           Names: all,basic,speed-of-light,memory,compute,occupancy,roofline,source,full.
USAGE
}

print_nopasswd_guide() {
  local ncu_path="$1"
  cat <<GUIDE

NCU 需要 sudo 权限，但当前 agent 不能交互式输入 sudo 密码。
请先为当前 CUDA 环境中的精确 ncu 路径配置 NOPASSWD，然后在下一次对话中重新发起 profile。

步骤 1：在你要 profile 的 CUDA 环境中找到 ncu。

  which ncu
  readlink -f \$(which ncu)

记住 readlink -f 输出的绝对路径，例如：

  /usr/local/cuda-12.4/bin/ncu

步骤 2：创建 sudoers 规则。

  sudo visudo -f /etc/sudoers.d/kernel-profiler-ncu

写入一行，替换 USERNAME 和 ncu 路径：

  USERNAME ALL=(root) NOPASSWD: $ncu_path

例如当前用户名是 USERNAME：

  USERNAME ALL=(root) NOPASSWD: $ncu_path

步骤 3：验证免密是否成功。

  sudo -n $ncu_path --version
  sudo -n $ncu_path --list-sections

步骤 4：多 CUDA 环境必须固定同一个 ncu。

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
STAGES="all"
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
  STAGE_BASIC="1"
  STAGE_SPEED="1"
  STAGE_MEMORY="1"
  STAGE_COMPUTE="1"
  STAGE_OCCUPANCY="1"
  STAGE_ROOFLINE="1"
  STAGE_SOURCE="1"
fi

if [[ "$RUN_FULL" == "1" ]]; then
  STAGE_FULL="1"
fi

if command -v "$NCU_BIN" >/dev/null 2>&1; then
  NCU_BIN="$(command -v "$NCU_BIN")"
fi
if command -v readlink >/dev/null 2>&1; then
  NCU_BIN="$(readlink -f "$NCU_BIN" 2>/dev/null || echo "$NCU_BIN")"
fi

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
      print_nopasswd_guide "$NCU_BIN" >&2
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
  echo "ncu_bin: $NCU_BIN"
  if [[ -n "$NVTX_RANGE" ]]; then echo "nvtx_range: $NVTX_RANGE"; fi
  echo
  echo "## ncu version"
  "$NCU_BIN" --version || true
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

run_ncu() {
  local label="$1"; shift
  local outfile="$1"; shift
  local stderr_file="$OUTPUT_DIR/details/${outfile}_stderr.txt"
  local cmd=("${SUDO_PREFIX[@]}" "$NCU_BIN" "${DEVICE_ARGS[@]}" "$@" "${FILTER[@]}" "${WINDOW[@]}" -f -o "$OUTPUT_DIR/details/$outfile" $EXTRA)
  echo "${cmd[*]} $TARGET_CMD" >> "$COMMANDS"
  echo "${SUDO_PREFIX[*]} $NCU_BIN ${DEVICE_ARGS[*]} $* ${FILTER[*]} ${WINDOW[*]} -f -o $OUTPUT_DIR/details/$outfile $EXTRA $TARGET_CMD"
  # shellcheck disable=SC2086
  set +e
  "${SUDO_PREFIX[@]}" "$NCU_BIN" ${DEVICE_ARGS[*]} "$@" "${FILTER[@]}" "${WINDOW[@]}" -f -o "$OUTPUT_DIR/details/$outfile" $EXTRA $TARGET_CMD 2> >(tee "$stderr_file" >&2)
  local status=$?
  set -e
  if [[ "$status" -ne 0 ]]; then
    if grep -Eqi "ERR_NVGPUCTRPERM|password is required|a password is required|permission|not permitted|Operation not permitted" "$stderr_file"; then
      print_nopasswd_guide "$NCU_BIN" >&2
    fi
    return "$status"
  fi
}

if [[ "$STAGE_BASIC" == "1" ]]; then
  run_ncu "basic" "01_basic" --set basic
fi
if [[ "$STAGE_SPEED" == "1" ]]; then
  run_ncu "speed_of_light" "02_speed_of_light" --section SpeedOfLight
fi
if [[ "$STAGE_MEMORY" == "1" ]]; then
  run_ncu "memory" "03_memory" --section MemoryWorkloadAnalysis --section SourceCounters
fi
if [[ "$STAGE_COMPUTE" == "1" ]]; then
  run_ncu "compute" "04_compute" --section ComputeWorkloadAnalysis --section InstructionStats --section SourceCounters
fi
if [[ "$STAGE_OCCUPANCY" == "1" ]]; then
  run_ncu "occupancy" "05_occupancy_launch" --section LaunchStats --section Occupancy --section SchedulerStats --section WarpStateStats
fi
if [[ "$STAGE_ROOFLINE" == "1" ]]; then
  if "${SUDO_PREFIX[@]}" "$NCU_BIN" --list-sections | grep -qi "SpeedOfLight_RooflineChart"; then
    run_ncu "roofline" "06_roofline" --section SpeedOfLight_RooflineChart
  else
    echo "Roofline section not found; inspect '$NCU_BIN --list-sections'." | tee "$OUTPUT_DIR/details/06_roofline_missing.txt"
  fi
fi
if [[ "$STAGE_SOURCE" == "1" && "$RUN_SOURCE" == "1" ]]; then
  run_ncu "source" "07_source" --section SourceCounters --page source --print-source sass
fi
if [[ "$STAGE_FULL" == "1" ]]; then
  run_ncu "full" "08_full" --set full
fi

for report in "$OUTPUT_DIR"/details/*.ncu-rep; do
  [[ -e "$report" ]] || continue
  csv="${report%.ncu-rep}_raw.csv"
  echo "${SUDO_PREFIX[*]} $NCU_BIN --import $report --page raw --csv > $csv" >> "$COMMANDS"
  "${SUDO_PREFIX[@]}" "$NCU_BIN" --import "$report" --page raw --csv > "$csv" || true
done

# Generate compact metric summary from all raw CSV files.
cat "$OUTPUT_DIR"/details/*_raw.csv > "$OUTPUT_DIR/details/metrics_raw.csv" 2>/dev/null || true
if [[ -s "$OUTPUT_DIR/details/metrics_raw.csv" ]]; then
  python3 "$(dirname "$0")/extract_ncu_metrics.py" --input "$OUTPUT_DIR/details/metrics_raw.csv" --output-dir "$OUTPUT_DIR/details" || true
fi

if [[ -f "$OUTPUT_DIR/details/07_source_raw.csv" ]]; then
  python3 "$(dirname "$0")/generate_source_hotspots.py" --input "$OUTPUT_DIR/details/07_source_raw.csv" --output "$OUTPUT_DIR/details/source_hotspots.csv" || true
elif [[ ! -f "$OUTPUT_DIR/details/source_hotspots.csv" ]]; then
  python3 "$(dirname "$0")/generate_source_hotspots.py" --input /dev/null --output "$OUTPUT_DIR/details/source_hotspots.csv" || true
fi

cat > "$OUTPUT_DIR/run_manifest.yaml" <<MANIFEST
profile_id: "$(basename "$OUTPUT_DIR")"
created_at: "$(date -Iseconds)"
backend: "nvidia-ncu"
ncu_bin: "$NCU_BIN"
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
  stages: "$STAGES"
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
