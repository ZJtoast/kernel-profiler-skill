# Portable Kernel Bottleneck Taxonomy

Use this taxonomy in final reports. Vendor-specific names may be shown in parentheses, but the classification should use these portable labels.

## Memory Bandwidth Bound

The kernel is limited by sustained movement through device memory or cache hierarchy.

Evidence:

- memory throughput near peak
- roofline memory-limited
- high external memory bytes
- low arithmetic intensity

## Memory Latency Bound

The kernel waits on memory, but bandwidth is not saturated.

Evidence:

- high memory-dependency stalls
- low eligible work
- low memory throughput
- insufficient occupancy or ILP

## Poor Memory Coalescing

Memory lanes generate inefficient transactions.

Evidence:

- high sectors/request or equivalent transaction expansion
- low useful bytes per transaction
- source load/store hotspots

## On-Chip Scratch Conflict

Software-managed scratchpad memory serializes due to bank or access conflicts.

Evidence:

- bank-conflict counters
- expanded wavefronts/transactions
- scratch memory stalls

## Compute Pipeline Bound

A compute pipeline is close to peak and dominates runtime.

Evidence:

- high compute throughput
- high specific pipeline utilization
- compute-bound roofline location
- instruction mix dominated by that pipeline

## Tensor/Matrix Engine Underuse

A matrix workload does not use available matrix engines efficiently.

Evidence:

- expected tensor/matrix instructions absent
- low tensor/matrix pipeline utilization
- scalar/vector math dominates a matrix-like kernel

## Occupancy / Resource Bound

Resources limit resident work and harm latency hiding or throughput.

Evidence:

- low theoretical occupancy due to registers/shared/block/warp limits
- low achieved occupancy paired with stalls

## Scheduler / Latency Hiding Failure

Schedulers lack ready work.

Evidence:

- low eligible waves/warps
- high stall reasons
- low issue rate
- low compute and memory throughput

## Register Spill / Local Scratch Bound

Private values spill into local/scratch memory.

Evidence:

- high local/scratch traffic
- local memory instructions in source/ISA view
- high register pressure

## Synchronization Bound

Execution time is dominated by barriers or waits.

Evidence:

- barrier/wait stalls
- source-level synchronization hotspots

## Divergence / Control-Flow Bound

Lanes follow different paths and reduce efficiency.

Evidence:

- branch resolving stalls
- predicated instruction waste
- divergent source regions
