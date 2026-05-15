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
  --full                    Also run --set full as details/08_full.
  --no-source               Skip source/SASS collection.
  --extra "ARGS"            Extra raw ncu options appended before target command.
  --runtime NAME           Target runtime label: native | python | python-triton. Default: native.
  --nvtx-range NAME        Add Nsight Compute NVTX include filter for a named range.
  --sudo                  Run ncu through sudo when not already root. Requires interactive/preauthorized sudo; never stores passwords.
USAGE
}

TARGET_CMD=""
KERNEL_REGEX=""
KERNEL_NAME="target_kernel"
OUTPUT_DIR="./profile/kernel_profile"
LAUNCH_SKIP="10"
LAUNCH_COUNT="1"
DEVICES=""
RUN_FULL="0"
RUN_SOURCE="1"
EXTRA=""
RUNTIME="native"
NVTX_RANGE=""
USE_SUDO="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target-cmd) TARGET_CMD="$2"; shift 2 ;;
    --kernel-regex) KERNEL_REGEX="$2"; shift 2 ;;
    --kernel-name) KERNEL_NAME="$2"; shift 2 ;;
    --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
    --launch-skip) LAUNCH_SKIP="$2"; shift 2 ;;
    --launch-count) LAUNCH_COUNT="$2"; shift 2 ;;
    --devices) DEVICES="$2"; shift 2 ;;
    --full) RUN_FULL="1"; shift ;;
    --no-source) RUN_SOURCE="0"; shift ;;
    --extra) EXTRA="$2"; shift 2 ;;
    --runtime) RUNTIME="$2"; shift 2 ;;
    --nvtx-range) NVTX_RANGE="$2"; shift 2 ;;
    --sudo) USE_SUDO="1"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$TARGET_CMD" || -z "$KERNEL_REGEX" ]]; then
  usage >&2
  exit 2
fi

mkdir -p "$OUTPUT_DIR/details" "$OUTPUT_DIR/visual"
COMMANDS="$OUTPUT_DIR/commands.sh"
ENVFILE="$OUTPUT_DIR/details/00_environment.txt"
: > "$COMMANDS"
chmod +x "$COMMANDS"

{
  echo "created_at: $(date -Iseconds)"
  echo "kernel_name: $KERNEL_NAME"
  echo "kernel_regex: $KERNEL_REGEX"
  echo "launch_skip: $LAUNCH_SKIP"
  echo "launch_count: $LAUNCH_COUNT"
  echo "target_cmd: $TARGET_CMD"
  echo "runtime: $RUNTIME"
  if [[ -n "$NVTX_RANGE" ]]; then echo "nvtx_range: $NVTX_RANGE"; fi
  echo
  echo "## ncu version"
  ncu --version || true
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
  local prefix=()
  if [[ "$USE_SUDO" == "1" && "${EUID:-$(id -u)}" != "0" ]]; then prefix=(sudo); fi
  local cmd=("${prefix[@]}" ncu "${DEVICE_ARGS[@]}" "$@" "${FILTER[@]}" "${WINDOW[@]}" -f -o "$OUTPUT_DIR/details/$outfile" $EXTRA)
  echo "${cmd[*]} $TARGET_CMD" >> "$COMMANDS"
  echo "ncu ${DEVICE_ARGS[*]} $* ${FILTER[*]} ${WINDOW[*]} -f -o $OUTPUT_DIR/details/$outfile $EXTRA $TARGET_CMD"
  # shellcheck disable=SC2086
  if [[ "$USE_SUDO" == "1" && "${EUID:-$(id -u)}" != "0" ]]; then
    sudo ncu ${DEVICE_ARGS[*]} "$@" "${FILTER[@]}" "${WINDOW[@]}" -f -o "$OUTPUT_DIR/details/$outfile" $EXTRA $TARGET_CMD
  else
    ncu ${DEVICE_ARGS[*]} "$@" "${FILTER[@]}" "${WINDOW[@]}" -f -o "$OUTPUT_DIR/details/$outfile" $EXTRA $TARGET_CMD
  fi
}

run_ncu "basic" "01_basic" --set basic
run_ncu "speed_of_light" "02_speed_of_light" --section SpeedOfLight
run_ncu "memory" "03_memory" --section MemoryWorkloadAnalysis --section SourceCounters
run_ncu "compute" "04_compute" --section ComputeWorkloadAnalysis --section InstructionStats --section SourceCounters
run_ncu "occupancy" "05_occupancy_launch" --section LaunchStats --section Occupancy --section SchedulerStats --section WarpStateStats

if ncu --list-sections | grep -qi "SpeedOfLight_RooflineChart"; then
  run_ncu "roofline" "06_roofline" --section SpeedOfLight_RooflineChart
else
  echo "Roofline section not found; inspect 'ncu --list-sections'." | tee "$OUTPUT_DIR/details/06_roofline_missing.txt"
fi

if [[ "$RUN_SOURCE" == "1" ]]; then
  run_ncu "source" "07_source" --section SourceCounters --page source --print-source sass
fi

if [[ "$RUN_FULL" == "1" ]]; then
  run_ncu "full" "08_full" --set full
fi

for report in "$OUTPUT_DIR"/details/*.ncu-rep; do
  [[ -e "$report" ]] || continue
  csv="${report%.ncu-rep}_raw.csv"
  echo "ncu --import $report --page raw --csv > $csv" >> "$COMMANDS"
  ncu --import "$report" --page raw --csv > "$csv" || true
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
