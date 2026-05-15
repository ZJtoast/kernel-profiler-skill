# Workload Stabilization Guide

Kernel profiles are only useful when the measured launch is representative. This guide defines the default stabilization policy.

## Universal rules

- Use the same input shape, seed, batch size, precision, and algorithm path across runs.
- Keep GPU clocks, power limit, MIG/MPS state, driver, CUDA version, and container image stable.
- Avoid profiling while other GPU workloads are active.
- Prefer one target GPU with `CUDA_VISIBLE_DEVICES` or backend-specific device selection.
- Record all assumptions in `run_manifest.yaml`.

## Microbenchmarks

Recommended default:

```yaml
profiling:
  warmup_skip: 5
  launch_count: 3
```

Use more launch samples when single-launch duration is very short. Treat ±2% as normal variation unless the user configures a different tolerance.

## Training loops

Recommended default:

```yaml
profiling:
  warmup_skip: 10
  launch_count: 1
```

Stabilize data order, dynamic shapes, dropout, autotuning, and mixed-precision settings. If algorithm selection changes during warmup, profile after the selection has settled.

## Inference workloads

Recommended default:

```yaml
profiling:
  warmup_skip: 10
  launch_count: 3
```

Keep batch size and sequence length fixed. For transformer workloads, separate prefill and decode if kernel behavior differs.

## Autotuned libraries

cuBLASLt, cuDNN, CUTLASS, Triton, TVM, and similar stacks may generate or choose different kernels during early iterations.

- Run discovery after warmup when possible.
- Use NVTX range or regex filters once the target kernel name is known.
- Record library versions and relevant environment variables.

## Random variation policy

Default tolerance: ±2%.

- Within ±2%: normal variation.
- Beyond ±2% with consistent direction: material change.
- Beyond ±2% but inconsistent across repeated samples: unstable workload; report as inconclusive and recommend stabilization.

## Python/Triton Targets

Triton targets need extra stabilization because the first launches may include JIT compilation, cache population, and autotune candidate execution.

Recommended defaults:

| Workload shape | Warmup policy | Launch window |
|---|---|---|
| Single Triton JIT kernel, fixed shape | Warm up at least 20 matching launches | `launch-skip 20`, `launch-count 1` |
| Triton autotune enabled | Run or fix autotune before final collection | fixed config preferred |
| Dynamic shapes | One profile per shape | include shape in report/profile id |
| Very short kernels | Warm up JIT, collect 3+ launches | compare medians where possible |

The benchmark should synchronize before and after the profiled loop. This keeps the profile window stable without changing the kernel-only scope.
