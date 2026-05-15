# NVIDIA Nsight Compute Kernel Profiling Guide

This is a normalized operational guide for using NVIDIA Nsight Compute (`ncu`) as the default backend of Kernel Profiler Skill. It is derived from public NVIDIA Nsight Compute documentation and the `slowlyC/agent-gpu-skills` CUDA skill reference organization. Preserve attribution when redistributing.

## Scope

Use `ncu` to answer: **why is this selected CUDA kernel slow?**

Do not use this guide for application timeline diagnosis, CPU bottlenecks, launch gaps, data loading, communication, or system-level utilization. Use a system profiler for those topics.

## Core Commands

```bash
ncu --version
ncu --list-sets
ncu --list-sections
ncu --query-metrics-mode all --query-metrics
ncu --set basic -o report ./app
ncu --set full -o report ./app
ncu --import report.ncu-rep --page raw --csv > raw.csv
ncu-ui report.ncu-rep
```

## Kernel Selection

Prefer exact or demangled regex filters:

```bash
ncu --kernel-name "my_kernel" ./app
ncu --kernel-name-base demangled --kernel-name regex:".*my_kernel.*" ./app
```

Use launch controls for warmup and repeated kernels:

```bash
ncu --launch-skip 10 --launch-count 1 ./app
```

Use `kernel-id` for precise filtering:

```bash
# context-id:stream-id:[name-operator:]kernel-name:invocation-nr
ncu --kernel-id ::regex:^.*my_kernel.*$:2 ./app
```

Use NVTX when the code can mark the region:

```bash
ncu --nvtx --nvtx-include "target_range/" --kernel-name regex:".*my_kernel.*" ./app
```

## Recommended Collection Order

1. `--set basic`
2. `--section SpeedOfLight`
3. Targeted sections:
   - `MemoryWorkloadAnalysis`
   - `ComputeWorkloadAnalysis`
   - `InstructionStats`
   - `LaunchStats`
   - `Occupancy`
   - `SchedulerStats`
   - `WarpStateStats`
   - `SpeedOfLight_RooflineChart`
   - `SourceCounters`
4. Source/SASS/PTX correlation.
5. Optional full run for archival evidence.

## Basic Profile

Command:

```bash
ncu --set basic \
    --kernel-name-base demangled \
    --kernel-name regex:"<kernel_filter>" \
    --launch-skip <N> --launch-count <M> \
    -f -o details/01_basic \
    <target_command>
```

Answer:

- Was the intended kernel selected?
- What is the duration?
- Is grid/block configuration sane?
- Are register/shared-memory resources high?
- Is theoretical or achieved occupancy very low?
- Are SM or memory throughputs obviously dominant?

## SpeedOfLight

Command:

```bash
ncu --section SpeedOfLight \
    --kernel-name-base demangled \
    --kernel-name regex:"<kernel_filter>" \
    --launch-skip <N> --launch-count <M> \
    -f -o details/02_speed_of_light \
    <target_command>
```

Inspect:

- SM throughput
- memory throughput
- compute vs memory proximity to peak
- memory breakdown: L1/TEX, L2, DRAM, shared
- compute breakdown: FP32, FP64, Tensor Core, integer, load/store, special function

Decision:

- Memory high, SM lower -> memory-bound candidate.
- SM high, memory lower -> compute-bound candidate.
- Both low -> latency, scheduling, occupancy, synchronization, or divergence candidate.

## MemoryWorkloadAnalysis

Command:

```bash
ncu --section MemoryWorkloadAnalysis \
    --section SourceCounters \
    --kernel-name-base demangled \
    --kernel-name regex:"<kernel_filter>" \
    --launch-skip <N> --launch-count <M> \
    -f -o details/03_memory \
    <target_command>
```

Inspect:

- DRAM throughput
- L1/TEX hit rate
- L2 hit rate
- global load/store requests and sectors
- sector/request ratio
- shared-memory bank conflicts
- local memory usage
- replay overhead
- cache-line utilization
- Mem Busy, Max Bandwidth, Mem Pipes Busy

Useful metric families:

```text
dram__throughput.*
lts__throughput.*
l1tex__throughput.*
l1tex__t_sectors_pipe_lsu_mem_global_op_ld.*
l1tex__t_requests_pipe_lsu_mem_global_op_ld.*
l1tex__t_sectors_pipe_lsu_mem_global_op_st.*
l1tex__t_requests_pipe_lsu_mem_global_op_st.*
l1tex__data_bank_conflicts_pipe_lsu_mem_shared_op_ld.*
l1tex__data_bank_conflicts_pipe_lsu_mem_shared_op_st.*
```

Interpretation:

- High sectors/request means poor memory transaction efficiency.
- High DRAM throughput with low arithmetic intensity usually indicates memory bandwidth pressure.
- High local memory traffic often indicates register spills or large per-thread arrays.
- Shared bank conflicts indicate on-chip scratch access serialization.

## ComputeWorkloadAnalysis and InstructionStats

Command:

```bash
ncu --section ComputeWorkloadAnalysis \
    --section InstructionStats \
    --section SourceCounters \
    --kernel-name-base demangled \
    --kernel-name regex:"<kernel_filter>" \
    --launch-skip <N> --launch-count <M> \
    -f -o details/04_compute \
    <target_command>
```

Inspect:

- FP32 pipeline utilization
- FP64 pipeline utilization
- Tensor Core pipeline utilization
- integer pipeline utilization
- load/store pipeline utilization
- IPC / issue rate
- instruction mix
- FMA usage
- Tensor Core instruction usage
- special-function/division/conversion pressure

Useful metric families:

```text
sm__throughput.*
smsp__throughput.*
smsp__inst_executed_pipe_fp32.*
smsp__inst_executed_pipe_fp64.*
smsp__inst_executed_pipe_tensor.*
smsp__inst_executed_pipe_alu.*
smsp__inst_executed_pipe_lsu.*
smsp__inst_issued.*
smsp__inst_executed.*
smsp__sass_thread_inst_executed_op_ffma_pred_on.*
smsp__sass_thread_inst_executed_op_hmma_pred_on.*
```

Interpretation:

- High compute pipeline use and roofline compute-bound position imply arithmetic saturation.
- Tensor kernels without tensor instructions indicate a missed tensor path.
- Many conversion/division/special-function operations may dominate pipelines.

## Occupancy, Launch, Scheduler, Warp State

Command:

```bash
ncu --section LaunchStats \
    --section Occupancy \
    --section SchedulerStats \
    --section WarpStateStats \
    --kernel-name-base demangled \
    --kernel-name regex:"<kernel_filter>" \
    --launch-skip <N> --launch-count <M> \
    -f -o details/05_occupancy_launch \
    <target_command>
```

Inspect:

- grid size
- block size
- registers per thread
- static and dynamic shared memory
- theoretical occupancy
- achieved occupancy
- active warps per SM
- eligible warps per scheduler
- issued warps per scheduler
- occupancy limiting factor
- warp stall reasons

Interpretation:

- Low occupancy matters only when it limits latency hiding or throughput.
- Theoretical occupancy limited by registers suggests register pressure.
- Theoretical occupancy limited by shared memory suggests per-block shared usage is high.
- High long scoreboard stalls usually indicate waiting on global/local memory.
- High short scoreboard stalls can indicate short-latency dependency or shared-memory pressure.
- Barrier stalls point to synchronization.

## Roofline

Command:

```bash
ncu --section SpeedOfLight_RooflineChart \
    --kernel-name-base demangled \
    --kernel-name regex:"<kernel_filter>" \
    --launch-skip <N> --launch-count <M> \
    -f -o details/06_roofline \
    <target_command>
```

If needed:

```bash
ncu --list-sections | rg -i roofline
```

Inspect:

- arithmetic intensity
- achieved performance
- applicable memory and compute roofs
- distance from roofline

Use roofline to decide whether optimization should reduce memory traffic, increase data reuse, or improve compute pipeline utilization.

## Source/SASS/PTX

Compile with line info:

```bash
nvcc -O3 -lineinfo ...
```

Collect:

```bash
ncu --section SourceCounters \
    --page source \
    --print-source sass \
    --kernel-name-base demangled \
    --kernel-name regex:"<kernel_filter>" \
    --launch-skip <N> --launch-count <M> \
    -f -o details/07_source \
    <target_command>
```

Look for:

- `LDG` / `STG`: global loads/stores
- `LDS` / `STS`: shared memory
- local-memory load/store instructions: spills or per-thread arrays
- `FFMA`, `FADD`, `FMUL`: FP32 math
- `HMMA`, `MMA`, `WGMMA`: tensor operations
- `BAR`: barrier synchronization
- branch instructions around divergent predicates

## Exporting Raw Metrics

```bash
ncu --import details/01_basic.ncu-rep --page raw --csv > details/01_basic_raw.csv
ncu --import details/02_speed_of_light.ncu-rep --page raw --csv > details/02_speed_of_light_raw.csv
```

Use raw metrics for automated parsing and visualization, but base final interpretation on stable section fields when available.
