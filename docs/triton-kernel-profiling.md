# Triton Kernel Profiling Guide

Triton kernels are profiled as GPU kernels launched by a Python process. The profiler target is the Python command, while the kernel filter targets the generated GPU kernel name. The workflow remains kernel-only: no Python timeline, dataloader diagnosis, or end-to-end tracing is included unless explicitly requested outside this skill.

## Target Shape

A Triton target uses `target.runtime: python-triton`:

```yaml
target:
  runtime: "python-triton"
  executable: "python3"
  args: ["bench_triton_hgemm.py", "--m", "4096", "--n", "4096", "--k", "4096"]
  python:
    interpreter: "python3"
    entry_kind: "script"
    script: "bench_triton_hgemm.py"
    jit_framework: "triton"

runtime_options:
  triton_enabled: true
  triton_kernel_hint: "hgemm_byzj_v0"
  triton_autotune_policy: "warmup_or_fixed_config"
  jit_warmup_required: true
  recommended_warmup_skip: 20
```

The collector still runs the same backend command pattern:

```bash
ncu --kernel-name-base demangled --kernel-name regex:'.*hgemm_byzj_v0.*' \
  --launch-skip 20 --launch-count 1 \
  python3 bench_triton_hgemm.py --m 4096 --n 4096 --k 4096
```

## Warmup and JIT Rules

Triton adds JIT compilation and, often, autotuning. These launches must not be confused with the measured kernel window.

Use these defaults unless the target file overrides them:

| Scenario | Recommended action |
|---|---|
| Plain Triton JIT kernel | `warmup_skip: 20`, `launch_count: 1` |
| `@triton.autotune` enabled | Prefer fixed config for profiling, or warm up all autotune candidates before collection |
| Dynamic shapes | Profile one shape at a time; include shape in `profile_id` or report target summary |
| Very short Triton kernel | Use `launch_count: 3` or more and compare medians when data is available |
| First-run cache miss | Run the benchmark once outside the final profile or increase skip count |

The benchmark should call `torch.cuda.synchronize()` or equivalent before and after the measured loop. This does not make profiling end-to-end; it stabilizes the kernel launch window.

## Kernel Naming

The Python function name may not match the generated GPU kernel name. The default filter is still generated from the requested kernel hint:

```yaml
kernel:
  name: "hgemm_byzj_v0"
  filter_mode: "regex"
  filter: ".*hgemm_byzj_v0.*"
```

If the filter misses, run discovery and rank candidates by:

1. requested hint match,
2. demangled kernel name quality,
3. duration,
4. launch count.

If the generated name is opaque, prefer adding a stable name/NVTX range in the benchmark and using `kernel.nvtx_range` or `--nvtx-range`.

## Source Attribution

Source/SASS/PTX attribution is best effort for Triton. The report must distinguish between:

- source line mapped to Triton/Python code,
- generated PTX/SASS available without reliable Python line mapping,
- no reliable source mapping available.

Do not report source-line evidence unless the profiler output actually contains a usable file/line association.

## Autotune Policy

Recommended policies:

```yaml
runtime_options:
  triton_autotune_policy: "warmup_or_fixed_config"
```

Accepted values:

| Value | Meaning |
|---|---|
| `fixed_config` | Profile a single known config. Best for reproducibility. |
| `warmup_or_fixed_config` | Default. Warm up JIT/autotune, then collect one stable kernel window. |
| `allow_autotune` | Permit autotune launches in the run, but mark the result as less stable. |

## Example Target Generation

```bash
python3 scripts/generate_profile_target.py \
  --runtime python-triton \
  --python-script bench_triton_hgemm.py \
  --args --m 4096 --n 4096 --k 4096 --iters 100 \
  --kernel hgemm_byzj_v0 \
  --requirement "visual report, source, roofline" \
  --output profile-target.yaml
```

When arguments begin with dashes, `--target-cmd` is often cleaner:

```bash
python3 scripts/generate_profile_target.py \
  --runtime python-triton \
  --target-cmd "python3 bench_triton_hgemm.py --m 4096 --n 4096 --k 4096 --iters 100" \
  --kernel hgemm_byzj_v0 \
  --requirement "visual report" \
  --output profile-target.yaml
```
