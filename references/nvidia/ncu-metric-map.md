# NVIDIA Nsight Compute Metric Map

Metric names can vary by Nsight Compute version and GPU architecture. Use this file as a search map, not as an immutable list.

## Lookup First

```bash
ncu --query-metrics-mode all --query-metrics | rg -i "<term>"
ncu --list-sections | rg -i "<section>"
```

## Portable Concept to NVIDIA Metric Families

| Portable concept | NVIDIA sections | Metric families / search terms |
|---|---|---|
| compute throughput | `SpeedOfLight`, `ComputeWorkloadAnalysis` | `sm__throughput`, `smsp__throughput` |
| memory throughput | `SpeedOfLight`, `MemoryWorkloadAnalysis` | `dram__throughput`, `lts__throughput`, `l1tex__throughput` |
| DRAM pressure | `MemoryWorkloadAnalysis` | `dram__bytes`, `dram__sectors`, `dram__throughput` |
| L2 behavior | `MemoryWorkloadAnalysis` | `lts__`, `l2`, `hit_rate` |
| L1/TEX behavior | `MemoryWorkloadAnalysis` | `l1tex__`, `hit_rate` |
| coalescing | `MemoryWorkloadAnalysis`, `SourceCounters` | `sectors`, `requests`, `global_op_ld`, `global_op_st` |
| shared bank conflict | `MemoryWorkloadAnalysis` | `bank_conflicts`, `shared_op_ld`, `shared_op_st` |
| local spill/scratch | `MemoryWorkloadAnalysis`, `SourceCounters` | `local`, `spill`, `ld.local`, `st.local` |
| occupancy | `Occupancy`, `LaunchStats` | `occupancy`, `warps_active`, `launch__occupancy_limit` |
| scheduler health | `SchedulerStats` | `eligible`, `issued`, `scheduler` |
| warp stalls | `WarpStateStats` | `stall`, `scoreboard`, `barrier`, `branch` |
| FP32 pipe | `ComputeWorkloadAnalysis`, `InstructionStats` | `pipe_fp32`, `ffma`, `fadd`, `fmul` |
| FP64 pipe | `ComputeWorkloadAnalysis`, `InstructionStats` | `pipe_fp64`, `dfma`, `dadd`, `dmul` |
| tensor pipe | `ComputeWorkloadAnalysis`, `InstructionStats` | `pipe_tensor`, `hmma`, `mma`, `wgmma` |
| integer pipe | `ComputeWorkloadAnalysis`, `InstructionStats` | `pipe_alu`, `integer`, `iadd`, `imul` |
| load/store pipe | `ComputeWorkloadAnalysis`, `InstructionStats` | `pipe_lsu`, `ld`, `st` |
| instruction mix | `InstructionStats`, `SourceCounters` | `sass_thread_inst_executed`, `opcode` |
| roofline | `SpeedOfLight_RooflineChart` | `roofline`, `arithmetic_intensity`, `flop` |

## Common Raw Metric Examples

```text
sm__throughput.avg.pct_of_peak_sustained_elapsed
dram__throughput.avg.pct_of_peak_sustained_elapsed
lts__throughput.avg.pct_of_peak_sustained_elapsed
l1tex__throughput.avg.pct_of_peak_sustained_elapsed
smsp__inst_issued.avg.per_cycle_active
smsp__inst_executed.avg.per_cycle_active
l1tex__t_sectors_pipe_lsu_mem_global_op_ld.sum
l1tex__t_requests_pipe_lsu_mem_global_op_ld.sum
l1tex__t_sectors_pipe_lsu_mem_global_op_st.sum
l1tex__t_requests_pipe_lsu_mem_global_op_st.sum
l1tex__data_bank_conflicts_pipe_lsu_mem_shared_op_ld.sum
l1tex__data_bank_conflicts_pipe_lsu_mem_shared_op_st.sum
```

Confirm exact names before use.
