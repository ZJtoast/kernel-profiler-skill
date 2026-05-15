---
name: kernel-profiler-skill
description: "Kernel-only GPU profiling workflow. Use for profiling, diagnosing, comparing, or reporting individual GPU kernels without expanding into end-to-end system tracing."
---

# Kernel Profiler Skill

This skill standardizes an industrial, kernel-only profiling workflow.

Do not expand into application timeline, CPU scheduling, launch-gap, dataloader, communication, or end-to-end system diagnosis unless the user explicitly changes scope. If system issues appear, record them as out-of-scope observations and continue with kernel-only evidence.

Python and Triton are supported as target runtimes. In those cases, the profiled target is the Python process and the selected object is still the generated GPU kernel. Keep the same kernel-only scope: no Python timeline diagnosis, dataloader investigation, or framework-level performance audit by default.

## Script-first operating rule

The `scripts/` directory is the executable control plane for this skill. Agents must call these scripts directly instead of recreating their logic in generated shell snippets, Python snippets, or prose instructions.

Use this script map as the default implementation path:

| Task | Required script |
|---|---|
| Generate `./profile/<id>/profile-target.yaml` from a compact request | `python3 scripts/generate_profile_target.py ...` |
| Collect Nsight Compute profile stages | `scripts/ncu_collect_kernel_profile.sh ...` |
| Discover kernels only as fallback | `scripts/discover_kernels.sh ./profile/<id>/profile-target.yaml ./profile/<id>/details` |
| Extract compact metrics from raw CSV | `python3 scripts/extract_ncu_metrics.py ...` |
| Generate source/SASS/PTX hotspot table | `python3 scripts/generate_source_hotspots.py ...` |
| Run optional bottleneck rules | `python3 scripts/bottleneck_decision_engine.py ...` |
| Run optional before/after comparison | `python3 scripts/compare_profiles.py ...` |
| Render optional visual report | `python3 scripts/visualize_profile_report.py ...` |

Do not inline or regenerate these scripts. Do not write a new collector, parser, hotspot extractor, comparison tool, visualization tool, or privilege wrapper unless the existing script is missing a required capability. If a capability is missing, make the smallest scoped patch to the existing script first, then call it.

Direct `ncu` commands in this file are reference examples, not the preferred execution mechanism. During real profiling, prefer `scripts/ncu_collect_kernel_profile.sh` with `--stages` to run the requested or evidence-justified profile stages.

## Reference material policy

The `references/` directory is part of this skill's required operating context, not optional background reading. Use it whenever profiler behavior, metric meaning, command syntax, bottleneck taxonomy, or architecture limits affect the answer.

Before running or interpreting a profile, consult the relevant reference files:

- `references/nvidia/ncu-guide.md` for the common `ncu` command flow: kernel filters, launch skip/count, basic/full sets, section collection, raw export, source export, and GUI handoff.
- `references/nvidia/ProfilingGuide.index.md` as the first stop for official Nsight Compute concepts; use it to find the right topic without reading the full guide.
- `references/nvidia/ProfilingGuide.md` when a precise Nsight Compute definition is needed: replay behavior, metric structure, hardware model, sections/rules, source metrics, NVTX/range profiling, roofline, or compatibility details.
- `references/nvidia/ncu-metric-map.md` to translate profiling questions into NVIDIA section names, metric families, search terms, and bottleneck evidence.
- `references/nvidia/architectures/README.md` to understand the architecture reference layout and lookup order.
- `references/nvidia/architectures/gpu_specs.yaml` for machine-readable GPU limits, product/chip fields, memory bandwidth, cache size, SM count, shared memory, registers, and occupancy ceilings.
- `references/nvidia/architectures/architecture-notes.md` for interpreting those architecture fields during kernel analysis.

Do not rely on memory alone for profiler metric names, section names, architecture limits, or flags. Prefer the local reference files first, then the installed profiler's own query commands such as `ncu --list-sections`, `ncu --list-sets`, and `ncu --query-metrics-mode all --query-metrics` when runtime confirmation is needed. If local references and profiler output disagree, report the discrepancy and prefer the profiler output for the current run.

Token-control rule: read only the files needed for the current decision. Use `rg` across `references/` to locate the relevant passage, then open the smallest useful file or section.


## Primary agent workflow

The primary entry point is a compact natural-language request, not a manually prepared target file. For example:

```text
/skill kernel-profiler-skill, profile kernel hgemm_byzj_v0 and generate a visual report
```

When invoked this way, perform the workflow below:

1. Parse the request into structured intent: kernel name/hint, runtime hints such as native CUDA or Python/Triton, visualization, source mapping, Roofline, regression, privilege preference, and any extra constraints.
2. Resolve the target command from repository context when it is not explicitly supplied. Search common benchmark and build entry points such as `README`, `CMakeLists.txt`, `Makefile`, `build/`, `bin/`, `examples/`, `bench*`, `scripts/run*`, and project-specific benchmark docs.
3. Call `scripts/generate_profile_target.py` to create `./profile/<kernel_profile_id>/profile-target.yaml`. Do not hand-write the file unless the generator cannot express the requested target or a small post-generation patch is required.
4. Use the kernel hint directly as the first profiler filter. For `hgemm_byzj_v0`, generate `filter_mode: regex` and `filter: .*hgemm_byzj_v0.*`. Do not run discovery before this step.
5. Validate unsupported or out-of-scope requirements recorded in `notes.unsupported_or_deferred_requirements` before collection.
6. Execute the staged profile by calling `scripts/ncu_collect_kernel_profile.sh`. Default to `--stages auto`: the collector runs `basic`, reads compact metrics, then runs one evidence-justified follow-up stage such as `memory`, `compute`, `occupancy`, or `speed-of-light`. If `privilege.mode` is `full_sudo`, pass `--sudo`; the collector must read the profiler path from `./profile/ncu_path` and ignore ad hoc `ncu` path guessing. Use `--stages all` only when explicitly requested.
7. If Nsight Compute requires privileged counters or `sudo -n` reports that a password is required, immediately stop the current profile attempt, send the NOPASSWD setup guide in the Privilege model section to the user, and wait for the next user message before doing any more profiling. Do not try another profile stage, do not run discovery, do not generate a handoff script, and do not ask for or use a sudo password.
8. Use the existing scripts to extract compact metrics, generate hotspot tables, run optional visuals/comparison reports, then write the normalized final report under `./profile/<kernel_profile_id>/`.

Manual `./profile/<id>/profile-target.yaml` editing is a supported secondary workflow. Direct script invocation is the default execution model.

## Input policy

The canonical intermediate file is `./profile/<kernel_profile_id>/profile-target.yaml`. The preferred entry point is a natural-language request; generate this file automatically whenever the target command and kernel hint can be resolved.

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
2. Convert a kernel hint into an `ncu` filter immediately, usually `regex:.*<escaped_kernel>.*`.
3. Translate supported extra requests into schema fields.
4. Detect unsupported requests and place them under `notes.unsupported_or_deferred_requirements`.
5. Keep discovery as a fallback, not as the default path.
6. Never store, read, print, pipe, or auto-type sudo passwords.

Example:

```bash
python3 scripts/generate_profile_target.py \
  --target-cmd "./build/bench --m 4096 --n 4096 --k 4096" \
  --kernel hgemm_byzj_v0 \
  --requirement "visual report, source, roofline"
```

Expected kernel section:

```yaml
kernel:
  name: hgemm_byzj_v0
  filter_mode: regex
  filter: .*hgemm_byzj_v0.*
  allow_discovery_fallback: true
```

## Privilege model

Professional GPU profilers may require privileged access to performance counters. The project supports two modes:

```yaml
privilege:
  mode: "none"                    # none | full_sudo
  password_storage: "forbidden"
profiling:
  ncu_bin: "ncu"                  # non-sudo only; full_sudo reads ./profile/ncu_path
```

### Mode 1 — `none`

Run profiler commands without sudo. This is the default and should be attempted first when the platform allows non-admin counter access.

### Mode 2 — `full_sudo`

Run the collector with non-interactive `sudo -n` for the path stored in `./profile/ncu_path`. This mode is allowed only when:

- current process is already root,
- `/etc/sudoers` grants narrow `NOPASSWD` permission for the exact path stored in `./profile/ncu_path`.

At skill start, ensure `./profile/ncu_path` exists. If it does not exist, create it with this default content:

```text
/usr/local/cuda/bin/ncu
```

Non-sudo mode runs `ncu` directly and does not need this file. Sudo mode must read this file and use its single path value for every profiler command.

Plaintext password storage is not supported. Do not write passwords into YAML, scripts, logs, commands, environment variables, shell history, or files such as `profile/sudokey`. Do not pipe passwords into `sudo -S`, read passwords from files, or auto-type passwords. Privilege must only be used for the profiler command path.

#### NOPASSWD setup guide

When `ncu` reports `ERR_NVGPUCTRPERM`, or `sudo -n "$(cat ./profile/ncu_path)" ...` fails because a password is required, output this guide to the user and stop until the user starts the next turn:

```bash
command -v ncu
readlink -f "$(command -v ncu)"
sudo visudo -f /etc/sudoers.d/kernel-profiler-ncu
```

Ask the user to choose one of the printed paths, configure exactly that path, then write the same path into `./profile/ncu_path`:

```text
USERNAME ALL=(root) NOPASSWD: /absolute/path/to/selected/cuda/bin/ncu
```

```bash
mkdir -p ./profile
printf '%s\n' '/absolute/path/to/selected/cuda/bin/ncu' > ./profile/ncu_path
```

Verify:

```bash
sudo -n "$(cat ./profile/ncu_path)" --version
sudo -n "$(cat ./profile/ncu_path)" --list-sections
```

After sending this guide, do not continue profiling in the same turn. The user must configure NOPASSWD, update `./profile/ncu_path`, and then start a new request.

## Output contract

Always generate:

```text
./profile/{kernel_name_profileid}/
├── profile-target.yaml
├── final_report.md
├── run_manifest.yaml
├── commands.sh
├── details/
│   ├── 00_environment.txt
│   ├── 00_discovery_raw.csv                 # if discovery was needed
│   ├── kernel_candidates.json                # if discovery was needed
│   ├── 01_basic_raw.csv
│   ├── 02_speed_of_light_raw.csv
│   ├── 03_memory_raw.csv
│   ├── 04_compute_raw.csv
│   ├── 05_occupancy_launch_raw.csv
│   ├── 06_roofline_raw.csv
│   ├── 07_source_raw.csv
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
2. Ensure `./profile/ncu_path` exists with default content `/usr/local/cuda/bin/ncu`; do not overwrite it if the user already edited it.
3. If a kernel name is available but no explicit filter is provided, generate a regex filter from the kernel name and proceed.
4. Enter discovery mode only if the filter is missing, produces no match, or needs disambiguation.
5. Detect profiler availability. In non-sudo mode use `ncu`; in sudo mode use `sudo -n "$(cat ./profile/ncu_path)"`.
6. Capture environment in `details/00_environment.txt`.
7. Check source mapping requirement. Prefer release build with line info, e.g. `nvcc -O3 -lineinfo`. Do not use debug-only `-G` for performance profiling unless explicitly requested.
8. Generate stable profile id from `{sanitized_kernel_name}_{YYYYMMDD_HHMMSS}` unless provided.

### Phase 1 — Kernel selection and discovery fallback

Default path: use the generated kernel filter directly. For a request like `hgemm_byzj_v0`, the initial filter should be equivalent to:

```text
regex:.*hgemm_byzj_v0.*
```

Run discovery only if the generated filter is absent, matches no kernel, or returns ambiguous candidates:

```bash
scripts/discover_kernels.sh ./profile/<id>/profile-target.yaml ./profile/<id>/details
```

Selection policy:

1. Prefer exact user hint match.
2. Prefer demangled kernel names.
3. Rank by user hint match, duration, then launch count.
4. If several candidates are plausible, choose the highest-cost candidate and record alternatives.
5. Never run full profile on all kernels.

For precise filtering, use supported filter modes such as exact name, regex, kernel-id, or NVTX range.

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

1. Profile the Python command with the collector script; do not try to profile the `.py` file as a source artifact by itself.
2. Use the requested Triton kernel name as the initial kernel filter.
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
  --output-dir ./profile/hgemm_byzj_v0_20260515_120000 \
  --stages auto
```

### Phase 3 — Staged profile

Default collection is one script call:

```bash
scripts/ncu_collect_kernel_profile.sh \
  --target-cmd "<target_command>" \
  --kernel-name "<kernel_name>" \
  --kernel-regex "<kernel_filter>" \
  --launch-skip <N> --launch-count <M> \
  --output-dir ./profile/<id> \
  --stages auto
```

Collector requirements:

1. Run `basic` first, write `details/01_basic_raw.csv`, and refresh `details/metrics_summary.json`.
2. Select exactly one follow-up stage from compact basic metrics unless the user explicitly requested more.
3. Write raw CSV directly. Do not generate `.ncu-rep`; do not print profiler data to the agent context; do not persist routine `*_stdout.txt` or `*_stderr.txt` files in `details/`.
4. Keep terminal output concise: stage name, selected follow-up, and artifact directory only.
5. If the kernel filter matches no profiled kernel, stop immediately, report the kernel/filter/target reason, and do not continue to later stages or privilege guidance.
6. Use `--stages all` only when explicitly requested.

Auto follow-up selection:

| Basic evidence | Follow-up stage |
|---|---|
| memory/DRAM utilization dominates | `memory` |
| SM utilization dominates | `compute` |
| achieved occupancy is low or far below theoretical | `occupancy` |
| SM and memory are both low, IPC is low | `occupancy` |
| basic lacks enough direction | `speed-of-light` |

Manual stage names are `basic`, `speed-of-light`, `memory`, `compute`, `occupancy`, `roofline`, `source`, and `full`. Run only stages justified by user request or evidence. If source attribution is needed, collect `source` and use `scripts/generate_source_hotspots.py` only as a retry path.

### Phase 4 — Post-processing

Use existing scripts only:

- Extract compact metrics: `python3 scripts/extract_ncu_metrics.py --input ./profile/<id>/details/metrics_raw.csv --output-dir ./profile/<id>/details`
- Retry source hotspots: `python3 scripts/generate_source_hotspots.py --input ./profile/<id>/details/07_source_raw.csv --output ./profile/<id>/details/source_hotspots.csv`
- Optional bottleneck rules: `python3 scripts/bottleneck_decision_engine.py --target ./profile/<id>/profile-target.yaml --metrics ./profile/<id>/details/metrics_summary.json --rules <rules.yaml> --output ./profile/<id>/details/bottleneck_decision.json`
- Optional comparison: `python3 scripts/compare_profiles.py --current ./profile/<id> --baseline auto --tolerance-pct 2.0 --output ./profile/<id>/comparison/regression_report.md`
- Optional visual report: `python3 scripts/visualize_profile_report.py ./profile/<id>/final_report.md ./profile/<id>/details ./profile/<id>/visual/profile_summary.png`

The optional bottleneck engine assists classification but does not replace agent reasoning. The final report must cite concrete metrics and source hotspots.

### Phase 5 — Final report

The final report must be compact, evidence-first, and reproducible. Include target summary, kernel filter, profiler version, privilege mode, commands, collected sections, bottleneck classification, evidence table, source/SASS/PTX hotspots when available, optimization hypotheses, confidence, limitations, and next profiling actions. Avoid dumping raw profiler output; link raw artifacts by path and summarize only decision-relevant metrics.

## Token-control rules for agents

1. Read `metrics_summary.json` before reading large CSV/text reports.
2. Read `source_hotspots.csv` before reading full source export.
3. Do not paste large profiler outputs into the final answer.
4. Only inspect raw metrics for unresolved evidence gaps.
5. Prefer table summaries and exact artifact paths.
6. If a section was not collected, say so and explain why.
