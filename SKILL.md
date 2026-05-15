---
name: kernel-profiler-skill
description: "Kernel-only GPU profiling workflow for professional profiler backends. Default backend is NVIDIA Nsight Compute (ncu), but the workflow is vendor-portable. Use for profiling, diagnosing, comparing, or reporting individual GPU kernels without expanding into end-to-end system tracing."
---

# Kernel Profiler Skill

This skill standardizes an industrial, kernel-only profiling workflow. The default backend is NVIDIA Nsight Compute (`ncu`). Other GPU vendors can replace the backend through `references/<vendor>/vendor-adapter-*.yaml` and a compatible metric alias map.

Do not expand into application timeline, CPU scheduling, launch-gap, dataloader, communication, or end-to-end system diagnosis unless the user explicitly changes scope. If system issues appear, record them as out-of-scope observations and continue with kernel-only evidence.

Python and Triton are supported as target runtimes. In those cases, the profiled target is the Python process and the selected object is still the generated GPU kernel. Keep the same kernel-only scope: no Python timeline diagnosis, dataloader investigation, or framework-level performance audit by default.

## Reference material policy

The `references/` directory is part of this skill's required operating context, not optional background reading. Use it whenever profiler behavior, metric meaning, backend command syntax, bottleneck taxonomy, architecture limits, or vendor-portability decisions affect the answer.

Before running or interpreting a profile, consult the relevant reference files:

- `references/nvidia/vendor-adapter-nvidia-ncu.yaml` for the default Nsight Compute backend commands, filters, sets, sections, export modes, and capability declarations.
- `references/nvidia/ncu-guide.md` for the common `ncu` command flow: kernel filters, launch skip/count, basic/full sets, section collection, raw export, source export, and GUI handoff.
- `references/nvidia/profilingguide.index.md` as the first stop for official Nsight Compute concepts; use it to find the right topic without reading the full guide.
- `references/nvidia/profilingguide.md` when a precise Nsight Compute definition is needed: replay behavior, metric structure, hardware model, sections/rules, source metrics, NVTX/range profiling, roofline, or compatibility details.
- `references/nvidia/ncu-metric-map.md` to translate profiling questions into NVIDIA section names, metric families, search terms, and bottleneck evidence.
- `references/nvidia/architectures/README.md` to understand the architecture reference layout and lookup order.
- `references/nvidia/architectures/gpu_specs.yaml` for machine-readable GPU limits, product/chip fields, memory bandwidth, cache size, SM count, shared memory, registers, and occupancy ceilings.
- `references/nvidia/architectures/architecture-notes.md` for interpreting those architecture fields during kernel analysis.
- `references/portable/metric-aliases.yaml` for vendor-neutral metric aliases and portable analysis terminology.
- `references/portable/portable-bottleneck-taxonomy.md` for normalized bottleneck classes.
- `references/portable/rules/bottleneck_rules.yaml` only when the optional bottleneck decision engine is enabled.
- `references/portable/vendor-porting-guide.md` when adding or validating a non-NVIDIA backend.

Do not rely on memory alone for profiler metric names, section names, architecture limits, or backend flags. Prefer the local reference files first, then the installed profiler's own query commands such as `ncu --list-sections`, `ncu --list-sets`, and `ncu --query-metrics-mode all --query-metrics` when runtime confirmation is needed. If local references and profiler output disagree, report the discrepancy and prefer the profiler output for the current run.

Token-control rule: read only the files needed for the current decision. Use `rg` across `references/` to locate the relevant passage, then open the smallest useful file or section.


## Primary agent workflow

The primary entry point is a compact natural-language request, not a manually prepared target file. For example:

```text
/skill kernel-profiler-skill, profile kernel hgemm_byzj_v0 and generate a visual report
```

When invoked this way, perform the workflow below:

1. Parse the request into structured intent: kernel name/hint, runtime hints such as native CUDA or Python/Triton, visualization, source mapping, Roofline, regression, privilege preference, and any extra constraints.
2. Resolve the target command from repository context when it is not explicitly supplied. Search common benchmark and build entry points such as `README`, `CMakeLists.txt`, `Makefile`, `build/`, `bin/`, `examples/`, `bench*`, `scripts/run*`, and project-specific benchmark docs.
3. Call `scripts/generate_profile_target.py` to create `profile-target.yaml`. Do not hand-write the file unless the generator cannot express the requested target or a small post-generation patch is required.
4. Use the kernel hint directly as the first profiler filter. For `hgemm_byzj_v0`, generate `filter_mode: regex` and `filter: .*hgemm_byzj_v0.*`. Do not run discovery before this step.
5. Validate unsupported or out-of-scope requirements recorded in `notes.unsupported_or_deferred_requirements` before collection.
6. Execute the staged profile, or generate a manual sudo handoff script when the privilege mode requires terminal interaction outside the agent process.
7. Extract compact metrics, generate hotspot tables, generate optional visuals/comparison reports, then write the normalized final report under `./profile/<kernel_profile_id>/`.

Manual `profile-target.yaml` editing and direct script invocation are supported secondary workflows. They are not the default interaction model.

## Input policy

The canonical intermediate file is `profile-target.yaml`. The preferred entry point is a natural-language request; generate this file automatically whenever the target command and kernel hint can be resolved.

Minimum natural-language input:

```text
Profile kernel <kernel_name_or_hint> in <executable or command>.
```

Triton example:

```text
Profile Triton kernel hgemm_byzj_v0 in python3 bench_triton_hgemm.py, with visual report.
```

Default kernel-filter policy:

```yaml
kernel:
  name: "<kernel_name_or_hint>"
  filter_mode: "regex"
  filter: ".*<escaped_kernel_name_or_hint>.*"
  allow_discovery_fallback: true
```

Do not run a separate discovery pass merely because `filter_mode` is `auto` or because the request only names a kernel. Use the kernel name directly as the first profiler filter. Run discovery only when:

1. no kernel name/hint is available,
2. the generated filter matches no kernel, or
3. several plausible kernels must be disambiguated before an expensive full profile.

Never run full profile against all kernels.

## Auto target generation

Use `scripts/generate_profile_target.py` for compact requests. The generator must:

1. Fill target executable, args, working directory, and kernel hint when available.
2. Convert a kernel hint into a backend filter immediately, usually `regex:.*<escaped_kernel>.*`.
3. Translate supported extra requests into schema fields.
4. Detect unsupported requests and place them under `notes.unsupported_or_deferred_requirements`.
5. Keep discovery as a fallback, not as the default path.
6. Never store sudo passwords.

Example:

```bash
python3 scripts/generate_profile_target.py \
  --target-cmd "./build/bench --m 4096 --n 4096 --k 4096" \
  --kernel hgemm_byzj_v0 \
  --requirement "visual report, source, roofline" \
  --output profile-target.yaml
```

Expected kernel section:

```yaml
kernel:
  name: hgemm_byzj_v0
  filter_mode: regex
  filter: .*hgemm_byzj_v0.*
  allow_discovery_fallback: true
```

Supported extra-request classes:

- native CUDA/C++ executable targets
- Python process targets
- Triton JIT kernel targets launched from Python
- basic/full profile level
- visual report toggle
- source/SASS/PTX attribution
- memory/compute/occupancy/roofline collection
- before/after regression mode
- privilege mode selection

Unsupported by default:

- Triton autotune search quality analysis outside the selected kernel window
- Python framework timeline diagnosis
- end-to-end timeline diagnosis
- CPU scheduling diagnosis
- dataloader/network/MPI communication profiling
- power tuning or overclocking
- system-wide tracing
- storing or piping sudo passwords

## Privilege model

Professional GPU profilers may require privileged access to performance counters. The project supports three modes:

```yaml
privilege:
  mode: "none"                    # none | authorized_sudo | manual_sudo_script
  password_storage: "forbidden"
```

### Mode 1 — `none`

Run profiler commands without sudo. This is the default and should be attempted first when the platform allows non-admin counter access.

### Mode 2 — `authorized_sudo`

Run the collector directly with sudo only when the environment is already safe for non-interactive privileged execution, for example:

- current process is already root,
- sudo credentials are already cached by an operator, or
- `/etc/sudoers` grants narrow `NOPASSWD` permission for the profiling command path.

Plaintext password storage is not supported. Do not write passwords into YAML, scripts, logs, commands, environment variables, or shell history. Do not pipe passwords into `sudo -S`. Privilege must only be used for the profiler command path.

### Mode 3 — `manual_sudo_script`

Generate `run_profile_with_sudo.sh` and let an operator run it in a real terminal. The generated script is intended to be launched as one privileged script:

```bash
sudo bash ./profile/<profile_id>/run_profile_with_sudo.sh
```

If launched without sudo, the script re-executes itself through sudo once, then runs profiler commands internally without prefixing each profiler invocation with sudo.

Recommended preflight:

```bash
ncu --version
ncu --list-sections
nvidia-smi || true
```

If `ERR_NVGPUCTRPERM` or equivalent appears, update `run_manifest.yaml`, generate `run_profile_with_sudo.sh` when permitted, and report the permission issue.

Manual handoff example:

```bash
python3 scripts/create_sudo_profile_handoff.py \
  --target-cmd "./build/bench --iters 100" \
  --kernel-name hgemm_byzj_v0 \
  --kernel-regex ".*hgemm_byzj_v0.*" \
  --launch-skip 10 \
  --launch-count 1 \
  --output-dir ./profile/hgemm_byzj_v0_20260515_120000 \
  --script ./profile/hgemm_byzj_v0_20260515_120000/run_profile_with_sudo.sh
```

Then run:

```bash
sudo bash ./profile/hgemm_byzj_v0_20260515_120000/run_profile_with_sudo.sh
```

## Output contract

Always generate:

```text
./profile/{kernel_name_profileid}/
├── final_report.md
├── run_manifest.yaml
├── commands.sh
├── run_profile_with_sudo.sh                 # only when manual sudo handoff is needed
├── details/
│   ├── 00_environment.txt
│   ├── 00_discovery_raw.csv                 # if discovery was needed
│   ├── kernel_candidates.json                # if discovery was needed
│   ├── 01_basic.*
│   ├── 02_speed_of_light.*
│   ├── 03_memory.*
│   ├── 04_compute.*
│   ├── 05_occupancy_launch.*
│   ├── 06_roofline.*
│   ├── 07_source.*
│   ├── metrics_raw.csv
│   ├── metrics_summary.json
│   ├── metrics_extracted.jsonl
│   ├── source_hotspots.csv
│   └── bottleneck_decision.json              # only when optional engine is enabled
├── comparison/
│   └── regression_report.md                  # only when optional regression mode is enabled
└── visual/
    └── profile_summary.png                   # only if enabled
```

The final report must include target summary, kernel filter, profiler version, privilege mode, exact commands, collected sections, bottleneck classification, evidence table, source/SASS/PTX hotspots, optimization hypotheses, confidence level, limitations, and next profiling actions.

## Workflow

### Phase 0 — Preflight

1. Resolve target path, working directory, environment variables, privilege policy, and kernel filter.
2. If a kernel name is available but no explicit filter is provided, generate a regex filter from the kernel name and proceed.
3. Enter discovery mode only if the filter is missing, produces no match, or needs disambiguation.
4. Detect profiler availability through the vendor adapter.
5. Capture environment in `details/00_environment.txt`.
6. Check source mapping requirement. Prefer release build with line info, e.g. `nvcc -O3 -lineinfo`. Do not use debug-only `-G` for performance profiling unless explicitly requested.
7. Generate stable profile id from `{sanitized_kernel_name}_{YYYYMMDD_HHMMSS}` unless provided.

### Phase 1 — Kernel selection and discovery fallback

Default path: use the generated kernel filter directly. For a request like `hgemm_byzj_v0`, the initial backend filter should be equivalent to:

```text
regex:.*hgemm_byzj_v0.*
```

Run discovery only if the generated filter is absent, matches no kernel, or returns ambiguous candidates:

```bash
scripts/discover_kernels.sh profile-target.yaml ./profile/<id>/details
```

Selection policy:

1. Prefer exact user hint match.
2. Prefer demangled kernel names.
3. Rank by user hint match, duration, then launch count.
4. If several candidates are plausible, choose the highest-cost candidate and record alternatives.
5. Never run full profile on all kernels.

For precise filtering, use backend-supported filter modes such as exact name, regex, kernel-id, or NVTX range.

### Phase 2 — Stabilize launch window

Default launch-window policy:

- If the user provided `warmup_skip` and `launch_count`, use them.
- For iterative/training/benchmark programs: `launch-skip 10`, `launch-count 1`.
- For deterministic microbenchmarks: `launch-skip 5`, `launch-count 3`.
- For Triton JIT kernels: default to `launch-skip 20`, `launch-count 1` unless a fixed benchmark window is known. Warm up JIT and autotune launches before collecting evidence.
- For very short kernels: collect several launches, then compare medians if supported.
- Treat ±2% as normal random variation unless configured otherwise.

See `docs/workload-stabilization-guide.md` and `docs/triton-kernel-profiling.md`.

### Triton/Python runtime handling

When `target.runtime` is `python-triton`:

1. Profile the Python command with the normal backend collector; do not try to profile the `.py` file as a source artifact by itself.
2. Use the requested Triton kernel name as the initial backend kernel filter.
3. Treat JIT compilation and autotune launches as warmup unless `runtime_options.triton_autotune_policy: allow_autotune` is explicitly set.
4. Prefer fixed Triton configs for final evidence runs.
5. Require explicit synchronization around the benchmark/profiled loop when practical.
6. Mark source attribution as `best_effort` unless the profiler output proves a reliable Python/Triton source line mapping.
7. If the generated kernel name does not match the Python function name, run discovery fallback and record the resolved generated name in the report.

Example direct collection:

```bash
scripts/ncu_collect_kernel_profile.sh \
  --runtime python-triton \
  --target-cmd "python3 bench_triton_hgemm.py --m 4096 --n 4096 --k 4096" \
  --kernel-name hgemm_byzj_v0 \
  --kernel-regex ".*hgemm_byzj_v0.*" \
  --launch-skip 20 \
  --launch-count 1 \
  --output-dir ./profile/hgemm_byzj_v0_20260515_120000
```

### Phase 3 — Basic profile

Purpose:

- Confirm selected kernel.
- Identify obvious bottlenecks.
- Check launch configuration, occupancy, SM utilization, and memory utilization.

NVIDIA example:

```bash
ncu --set basic \
  --kernel-name-base demangled \
  --kernel-name regex:"<kernel_filter>" \
  --launch-skip <N> --launch-count <M> \
  -f -o details/01_basic \
  <target_command>
```

Extract compact metrics:

```bash
ncu --import details/01_basic.ncu-rep --page raw --csv > details/metrics_raw.csv
python3 scripts/extract_ncu_metrics.py --input details/metrics_raw.csv --output-dir details
```

### Phase 4 — High-level bottleneck profile

Collect Speed of Light:

```bash
ncu --section SpeedOfLight \
  --kernel-name-base demangled \
  --kernel-name regex:"<kernel_filter>" \
  --launch-skip <N> --launch-count <M> \
  -f -o details/02_speed_of_light \
  <target_command>
```

Classify with evidence:

| Evidence | Classification | Next profile |
|---|---|---|
| Memory throughput near peak, SM lower | likely memory-bound | MemoryWorkloadAnalysis |
| SM throughput near peak, memory lower | likely compute-bound | ComputeWorkloadAnalysis + InstructionStats |
| Both low, high stalls, low eligible warps | likely latency/scheduler-bound | SchedulerStats + WarpStateStats |
| Low occupancy with resource limit | occupancy/resource-bound | LaunchStats + Occupancy |
| Arithmetic intensity below roofline knee | bandwidth-bound by model | Roofline + memory |
| High barrier/synchronization stalls | synchronization-bound | SourceCounters + WarpStateStats |

### Phase 5 — Targeted profiles

Run only the sections justified by evidence. If uncertain, run memory, compute, occupancy, roofline, and source in that order.

#### Memory

Collect `MemoryWorkloadAnalysis`, `MemoryWorkloadAnalysis_Chart`, and `SourceCounters`.

Analyze DRAM throughput, L1/TEX hit rate, L2 hit rate, global load/store requests and sectors, sectors/request, memory transactions, shared bank conflicts, local memory/spill symptoms, cache-line utilization, replay overhead, Mem Busy, Max Bandwidth, and Mem Pipes Busy.

Metric lookup procedure:

```bash
ncu --query-metrics-mode all --query-metrics | rg -i "dram|l2|l1tex|sector|request|bank|local|replay"
rg -i "DRAM Throughput|L2 Hit Rate|sector|bank conflict|Mem Busy|Max Bandwidth|Mem Pipes Busy" references/
```

Prefer report field names over hard-coded metrics when profiler versions differ.

#### Compute

Collect `ComputeWorkloadAnalysis`, `InstructionStats`, and `SourceCounters`.

Analyze FP32/FP64/Tensor Core utilization, integer pipeline, load/store pipeline, IPC, instruction mix, FMA use, tensor instruction use, and whether a specific pipeline is saturated.

#### Occupancy and launch

Collect `LaunchStats`, `Occupancy`, `SchedulerStats`, and `WarpStateStats`.

Analyze block size, grid size, registers per thread, static/dynamic shared memory, theoretical occupancy, achieved occupancy, active warps per SM, eligible warps per scheduler, and the limiting resource: register, shared memory, block limit, thread limit, or warp limit.

Use `references/nvidia/architectures/gpu_specs.yaml` to resolve architecture-specific limits such as maximum resident blocks per SM and shared memory per SM.

#### Roofline

Collect the backend roofline section when supported. Use it to decide whether the kernel is memory-bound or compute-bound by arithmetic intensity, not just by throughput percentages.

#### Source, SASS, and PTX attribution

Export source page and generate a standard hotspot table:

```bash
ncu --import details/07_source.ncu-rep --page source --print-source sass > details/07_source.txt
python3 scripts/generate_source_hotspots.py --input details/07_source.txt --output details/source_hotspots.csv
```

Every primary bottleneck should map to at least one of:

- source file and line
- SASS opcode family
- PTX opcode family
- explicit explanation for unavailable source mapping

### Phase 6 — Optional bottleneck decision engine

Default: disabled.

Enable only when the user requests rule-based classification or target file sets:

```yaml
analysis:
  enable_bottleneck_decision_engine: true
```

Run:

```bash
python3 scripts/bottleneck_decision_engine.py \
  --target profile-target.yaml \
  --metrics details/metrics_summary.json \
  --rules references/portable/rules/bottleneck_rules.yaml \
  --output details/bottleneck_decision.json
```

The engine assists classification but does not replace human/agent reasoning. The final report must cite the concrete metrics and source hotspots.

### Phase 7 — Optional before/after regression mode

Default: disabled.

Enable:

```yaml
analysis:
  enable_regression_compare: true
  compare_baseline: "auto"
  random_variation_tolerance_pct: 2.0
```

Baseline resolution for `auto`:

1. Search the current output root for the latest previous profile directory with the same kernel-name prefix.
2. Require a valid `details/metrics_summary.json` in the baseline directory.
3. If no valid baseline exists, write an inconclusive report and request explicit baseline path.
4. Never compare across unrelated kernel names unless the user explicitly gives the baseline path.

Run:

```bash
python3 scripts/compare_profiles.py \
  --current ./profile/<current_profile_id> \
  --baseline auto \
  --tolerance-pct 2.0 \
  --output ./profile/<current_profile_id>/comparison/regression_report.md
```

Regression report requirements:

- concrete baseline/current values
- absolute delta
- percentage delta
- judgment per metric
- overall verdict
- ±2% default noise tolerance
- explanation of lower-is-better vs higher-is-better metrics
- inconclusive state when baseline or metrics are missing

### Phase 8 — Optional visual report

Default: disabled. If enabled, check Python packages first and fail with install guidance if missing.

```bash
python3 scripts/visualize_profile_report.py ./profile/<id>/final_report.md ./profile/<id>/details ./profile/<id>/visual/profile_summary.png
```

### Phase 9 — Final report

The final report must be compact, evidence-first, and reproducible. Avoid dumping raw profiler output. Link raw artifacts by path and summarize only the decision-relevant metrics.

## Token-control rules for agents

1. Read `metrics_summary.json` before reading large CSV/text reports.
2. Read `source_hotspots.csv` before reading full source export.
3. Do not paste large profiler outputs into the final answer.
4. Only inspect raw metrics for unresolved evidence gaps.
5. Prefer table summaries and exact artifact paths.
6. If a section was not collected, say so and explain why.

## Vendor porting

A vendor backend must provide:

- profiler command mapping
- kernel discovery method
- exact/regex/id/range filtering support or equivalent
- basic, memory, compute, occupancy, roofline, and source/ISA collection mapping
- raw metric export method
- source/ISA correlation method
- conformance declaration in adapter YAML

Run:

```bash
python3 scripts/vendor_conformance_check.py --adapter references/nvidia/vendor-adapter-nvidia-ncu.yaml
```
