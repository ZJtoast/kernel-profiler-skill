# Nsight Compute Profiling Guide Index

This file is a compact lookup index for `references/nvidia/ProfilingGuide.md` or the official NVIDIA Nsight Compute Profiling Guide.

It is intentionally short. Use it to route kernel-profiling questions to the right Nsight Compute concepts, sections, and search terms before opening the full guide.

## Lookup order

1. Read this index.
2. Check the local metric aliases and backend adapter:
   - `references/portable/metric-aliases.yaml`
   - `references/nvidia/vendor-adapter-nvidia-ncu.yaml`
   - `references/nvidia/architectures/gpu_specs.yaml`
3. If a precise NVIDIA definition is required, open the official guide link recorded in `references/nvidia/ProfilingGuide.md` or browse the NVIDIA Nsight Compute documentation.
4. Do not read the full guide as the first step for routine kernel profiling.

## External source

- NVIDIA Nsight Compute Profiling Guide: https://docs.nvidia.com/nsight-compute/ProfilingGuide/index.html

## Main chapter routing

| Need | Search terms in the full guide | Notes |
|---|---|---|
| Understand how Nsight Compute profiles a process | `Profiling Applications` | NCU launches or attaches to the target process and intercepts CUDA kernel launches. |
| Choose `basic`, `full`, sections, or metrics | `Metric Collection`, `Sets and Sections` | Default is the `basic` set when no `--set`, `--section`, or `--metrics` is provided. |
| Understand section meanings | `Sections and Rules` | Primary lookup for `SpeedOfLight`, `MemoryWorkloadAnalysis`, `ComputeWorkloadAnalysis`, `LaunchStats`, `Occupancy`, `SchedulerStats`, `WarpStateStats`, and `SourceCounters`. |
| Understand replay overhead | `Replay`, `Kernel Replay`, `Application Replay`, `Range Replay`, `Overhead` | More sections and metrics can require multiple replay passes. |
| Profile NVTX ranges or grouped workloads | `Range Replay`, `Defining Ranges`, `NVTX Ranges` | Use for narrow ranges, concurrent kernels, or API/kernel groups. |
| Profile CUDA Graph workloads | `Graph Profiling` | Some instruction-level/source metrics may be unavailable. |
| Sweep launch parameters | `Profile Series` | Useful when block size, shared memory, or profile parameters need systematic comparison. |
| Decode metric names | `Metrics Structure`, `Metrics Naming Conventions`, `Metrics Entities` | Use before inventing metric names. |
| Understand GPU execution model | `Hardware Model`, `Compute Model`, `Streaming Multiprocessor` | Grid/block/thread, CTA, warp, SM, SMSP, schedulers, pipelines. |
| Interpret memory behavior | `Memory`, `Caches`, `Memory Chart`, `Memory Tables`, `Shared Memory`, `L1/TEX Cache`, `L2 Cache`, `Device Memory` | Route for memory bottlenecks, cache behavior, sector/request, and bank conflicts. |
| Interpret stall reasons | `Warp Stall Reasons`, `Warp Stall Reasons (Not Issued)`, `Source Metrics` | Use with scheduler evidence; do not over-focus on stalls when issue efficiency is already good. |
| Check launch metrics | `Launch Metrics` | `launch__*` metrics are kernel-launch properties and usually do not require replay. |
| Check occupancy metrics | `Occupancy Metrics` | Use with architecture limits and launch configuration. |
| Stabilize results | `Reproducibility`, `Serialization`, `Clock Control`, `Cache Control`, `Persistence Mode` | Use for noisy runs, before/after comparisons, or CI. |
| Handle MIG/MPS | `Multi Instance GPU`, `Multi-Process Service` | Use when MIG or MPS is active. |
| Interpret roofline | `Roofline Charts`, `Roofline Overview`, `Roofline Analysis`, `arithmetic intensity` | Cross-check with SpeedOfLight and workload sections. |

## Standard kernel-profiling path

### 1. First pass: basic profile

Use when the kernel is not yet characterized.

Search terms:

- `Sets and Sections`
- `basic set`
- `LaunchStats`
- `Occupancy`
- `SpeedOfLight`

Recommended command shape:

```bash
ncu --set basic \
    --kernel-name regex:".*<kernel>.*" \
    --launch-skip <N> \
    --launch-count 1 \
    -o <output> \
    <target command>
```

Basic answers:

- Which kernel is being profiled?
- Is the launch configuration plausible?
- Is theoretical/achieved occupancy obviously low?
- Are SM or memory resources roughly utilized?
- Is deeper targeted profiling needed?

### 2. High-level direction: SpeedOfLight

Search terms:

- `SpeedOfLight`
- `GPU Speed Of Light Throughput`
- `throughput`
- `pct_of_peak_sustained`
- `breakdown`

Use for:

- compute vs memory direction,
- top-level resource pressure,
- SM throughput,
- memory throughput,
- compute and memory breakdown.

Common metrics and query patterns:

```text
sm__throughput.avg.pct_of_peak_sustained_active
dram__throughput.avg.pct_of_peak_sustained_elapsed
l1tex__throughput.avg.pct_of_peak_sustained_active
lts__throughput.avg.pct_of_peak_sustained_active
breakdown:sm__throughput
breakdown:dram__throughput
breakdown:l1tex__throughput
breakdown:lts__throughput
```

Interpretation:

- High memory throughput and lower SM throughput usually points toward memory pressure.
- High SM throughput and lower memory throughput usually points toward compute pressure.
- Both low often points to launch size, occupancy, scheduler stalls, synchronization, dependency chains, or small workload size.

### 3. Memory path: MemoryWorkloadAnalysis

Search terms:

- `MemoryWorkloadAnalysis`
- `Memory Workload Analysis`
- `Mem Busy`
- `Max Bandwidth`
- `Mem Pipes Busy`
- `Memory Chart`
- `Memory Tables`
- `Shared Memory`
- `L1/TEX Cache`
- `L2 Cache`
- `Device Memory`

Use for:

- DRAM throughput,
- L1/TEX cache hit rate and throughput,
- L2 hit rate and throughput,
- global load/store efficiency,
- sector/request ratio,
- memory transactions,
- shared memory bank conflicts,
- local memory and register spilling evidence,
- cache line utilization,
- replay overhead.

Important families:

```text
dram__throughput.*
lts__throughput.*
l1tex__throughput.*
l1tex__t_sectors_*
l1tex__data_bank_conflicts*
smsp__sass_average_data_bytes_per_sector_mem_global*
smsp__sass_average_data_bytes_per_wavefront_mem_shared*
smsp__inst_executed_op_memory*
```

Evidence to report:

- exact metric values,
- whether the limiter looks like Mem Busy, Max Bandwidth, or Mem Pipes Busy,
- which memory level appears most constrained,
- source/SASS lines when source mapping is available.

### 4. Compute path: ComputeWorkloadAnalysis and InstructionStats

Search terms:

- `ComputeWorkloadAnalysis`
- `Compute Workload Analysis`
- `InstructionStats`
- `Instruction Statistics`
- `IPC`
- `Pipelines`
- `SASS`
- `instruction mix`
- `Instructions Per Opcode Metrics`
- `SASS Unit-Level Instructions Executed Metrics`

Use for:

- FP32 / FP64 / Tensor Core pipeline utilization,
- integer pipeline utilization,
- load/store pipeline utilization,
- IPC,
- instruction mix,
- FMA use,
- tensor instruction use,
- pipeline saturation or imbalance.

Useful families:

```text
sm__throughput.*
smsp__inst_executed*
smsp__pipe_*
smsp__issue_active*
smsp__inst_issued*
```

Evidence to report:

- dominant pipeline,
- instruction mix,
- underused expected pipeline, such as Tensor Cores not used when expected,
- source/SASS lines when available.

### 5. Occupancy and launch path: LaunchStats and Occupancy

Search terms:

- `LaunchStats`
- `Launch Statistics`
- `Occupancy`
- `active warps`
- `theoretical occupancy`
- `achieved occupancy`
- `resident blocks`
- `register usage`
- `shared memory`

Use for:

- block size,
- grid size,
- registers per thread,
- static shared memory,
- dynamic shared memory,
- theoretical occupancy,
- achieved occupancy,
- active warps per SM,
- occupancy limiter: registers, shared memory, block limit, warp limit.

Useful families:

```text
launch__block_size
launch__block_dim_x
launch__block_dim_y
launch__block_dim_z
launch__grid_dim_x
launch__grid_dim_y
launch__grid_dim_z
launch__registers_per_thread
launch__shared_mem_per_block_*
launch__occupancy_*
sm__warps_active.*
sm__maximum_warps.*
```

Interpretation rules:

- High occupancy is not automatically good.
- Low occupancy reduces latency hiding and should be examined when memory or dependency stalls are high.
- Large gap between theoretical and achieved occupancy may indicate imbalance, short waves, or runtime scheduling effects.

### 6. Scheduler and stall path: SchedulerStats and WarpStateStats

Search terms:

- `SchedulerStats`
- `Scheduler Statistics`
- `WarpStateStats`
- `Warp State Statistics`
- `Active Warps`
- `Eligible Warps`
- `Issued Warp`
- `warp states`
- `cycles per instruction`
- `Warp Stall Reasons`

Use for:

- eligible warps per scheduler,
- issued warps per scheduler,
- skipped issue slots,
- latency hiding quality,
- warp stall reason distribution.

Rule:

- Treat stall reasons as supporting evidence, not as the bottleneck by themselves.
- Prioritize stall reasons only when eligible/issued warp evidence shows poor scheduling progress.

Common stall categories to map:

```text
long_scoreboard       -> global/local memory dependency
short_scoreboard      -> shared memory or MIO dependency
barrier               -> block-level synchronization
branch_resolving      -> branch/control-flow handling
lg_throttle           -> local/global memory pipe pressure
mio_throttle          -> MIO/shared/texture pipe pressure
not_selected          -> eligible but scheduler selected another warp
imc_miss              -> immediate constant cache miss
```

### 7. Source attribution: SourceCounters and source metrics

Search terms:

- `SourceCounters`
- `Source Counters`
- `Source Metrics`
- `branch efficiency`
- `sampled warp stall reasons`
- `instruction-level source`
- `Instructions Per Opcode Metrics`

Use for:

- source line attribution,
- SASS/PTX/source correlation,
- branch efficiency,
- per-line sampled stalls,
- source hotspot table generation.

Output table should use fields similar to:

```text
source_file,line,function,sass_opcode,ptx_opcode,metric,value,stall_reason,bottleneck_class,confidence,evidence
```

Rules:

- Do not claim exact source-line causality unless source/SASS mapping is present.
- For Triton/JIT kernels, source mapping is best-effort unless line information is visible in the NCU source page or exported source output.

### 8. Roofline path

Search terms:

- `Roofline Charts`
- `Roofline Overview`
- `Roofline Analysis`
- `arithmetic intensity`

Use for:

- memory-bound vs compute-bound cross-check,
- arithmetic intensity,
- distance from roofline,
- whether optimization should reduce bytes moved or improve compute throughput.

Rule:

- Do not rely only on roofline. Cross-check with SpeedOfLight, MemoryWorkloadAnalysis, and ComputeWorkloadAnalysis.

## Replay mode routing

### Kernel replay

Search terms:

- `Kernel Replay`
- `save-and-restore`
- `replay pass`

Use when:

- profiling one kernel,
- default replay works,
- the kernel can be replayed deterministically by NCU.

Caveats:

- save/restore overhead grows with memory accessed or written,
- host-interdependent kernels can hang under kernel replay.

### Application replay

Search terms:

- `Application Replay`
- `deterministic`
- `app-replay-match`

Use when:

- kernel replay is unsuitable,
- avoiding kernel memory save/restore is useful,
- the whole application is deterministic enough to rerun.

Caveats:

- application setup is repeated,
- kernel matching depends on process, device, stream, context, name, grid, and order.

### Range replay

Search terms:

- `Range Replay`
- `Defining Ranges`
- `NVTX Ranges`
- `Profiler Start/Stop API`
- `Supported APIs`

Use when:

- profiling a narrow API/kernel range,
- keeping concurrent kernels together matters,
- NVTX or profiler API markers exist.

Caveats:

- unsupported CUDA APIs inside the range can fail,
- keep ranges narrow.

### Application range replay

Search terms:

- `Application Range Replay`
- `JIT-compiled kernels`
- `instruction-level SASS metrics`

Use when:

- a range should be captured by rerunning the application instead of direct capture/replay.

Caveat:

- instruction-level SASS metrics may not include JIT-compiled kernels inside the range.

### Graph profiling

Search terms:

- `Graph Profiling`
- `CUDA graphs`
- `kernel nodes`

Use when:

- the workload is launched through CUDA Graphs,
- graph-level behavior is more important than individual node behavior.

Caveat:

- some instruction-level/source metrics may be unavailable.

## Metrics structure cheat sheet

Search terms:

- `Metrics Structure`
- `Metrics Entities`
- `Metrics Naming Conventions`
- `Counters`
- `Ratios`
- `Throughputs`
- `roll-ups`
- `.sum`
- `.avg`
- `.pct_of_peak_sustained_active`
- `.pct_of_peak_sustained_elapsed`

Pattern:

```text
unit__(subunit?)_(pipestage?)_quantity_(qualifiers?).rollup.submetric
```

Common suffixes:

```text
.sum
.avg
.min
.max
.per_second
.per_cycle_active
.per_cycle_elapsed
.pct_of_peak_sustained_active
.pct_of_peak_sustained_elapsed
```

Examples:

```text
sm__throughput.avg.pct_of_peak_sustained_active
dram__throughput.avg.pct_of_peak_sustained_elapsed
l1tex__data_bank_conflicts_pipe_lsu.sum
```

## Hardware model cheat sheet

Search terms:

- `Hardware Model`
- `Compute Model`
- `Streaming Multiprocessor`
- `Memory`
- `Caches`
- `Texture/Surface`

Important concepts:

- Grid -> block/CTA -> thread.
- Warp size is 32 threads.
- CTAs are scheduled on SMs.
- CTA occupancy depends on threads, registers, shared memory, and hardware barriers.
- SMs are partitioned into SM sub-partitions.
- Each sub-partition contains a warp scheduler, register file, and execution pipelines.
- Shared memory bank conflicts serialize access.
- L1/TEX and L2 metrics are usually inspected through MemoryWorkloadAnalysis and Memory Tables.

For device-specific limits, use:

```text
references/nvidia/architectures/gpu_specs.yaml
```

## Reproducibility lookup

Search terms:

- `Reproducibility`
- `Serialization`
- `Clock Control`
- `Cache Control`
- `Persistence Mode`

Use for:

- noisy runs,
- before/after comparisons,
- CI or repeated profiles,
- explaining why small runtime changes should not be over-interpreted.

Skill rule:

- Treat runtime changes within +/- 2% as normal noise unless multiple independent metrics show a consistent directional change.

## Special configuration lookup

| Configuration | Search terms | Use when |
|---|---|---|
| MIG | `Multi Instance GPU`, `MIG` | GPU is partitioned. |
| MPS | `Multi-Process Service`, `MPS`, `Observation Window`, `Data Collection` | CUDA MPS is active. |
| CUDA Green Contexts | `CUDA Green Contexts`, `Green Contexts` | Application uses green contexts. |
| PM Sampling | `PM Sampling`, `Warp Sampling` | Need time-varying sampled metrics. |

## Triton / JIT routing

For Triton kernels, first read:

```text
docs/triton-kernel-profiling.md
```

Then use these guide terms only if needed:

- `Profiling Applications`
- `Replay`
- `Application Range Replay`
- `Source Metrics`
- `instruction-level SASS metrics`
- `JIT-compiled kernels`

Rules:

- Warm up JIT and autotune before collecting final metrics.
- Prefer a fixed Triton config for final evidence.
- Use the Python function name as a hint, not as guaranteed GPU kernel name.
- If the generated kernel name does not match, fallback to discovery.
- Source mapping is best-effort.

## Minimal decision map

| Question | Read first | Then read |
|---|---|---|
| Is this kernel memory-bound or compute-bound? | `SpeedOfLight` | `Roofline Charts`, `MemoryWorkloadAnalysis`, `ComputeWorkloadAnalysis` |
| Why is occupancy low? | `LaunchStats`, `Occupancy` | `Hardware Model`, `gpu_specs.yaml` |
| Which code line is responsible? | `SourceCounters` | `Source Metrics`, `Warp Stall Reasons`, `Instructions Per Opcode Metrics` |
| Why is profiling slow? | `Overhead` | `Replay`, `Sets and Sections` |
| Which replay mode should be used? | `Kernel Replay` | `Application Replay`, `Range Replay`, `Compatibility` |
| Does this work for Triton? | `docs/triton-kernel-profiling.md` | `Profiling Applications`, `Source Metrics` |

## Agent rules

- Prefer exact section names over broad semantic search.
- Use this index for routing, not for final definitions.
- Use backend adapter and metric alias files for command construction.
- Read the full guide only for exact semantics, limitations, or citations.
- Never run `--set full` across all kernels unless the workload is known to be small or the operator explicitly requests it.
- For JIT/Triton workloads, do not make strong line-level source claims unless source mapping evidence is present.
