# NVIDIA Architecture Notes for Kernel Profiling

This document explains how to use `gpu_specs.yaml` during kernel-only profiling.

## Runtime lookup order

1. Prefer runtime device properties from `nvidia-smi`, `cudaGetDeviceProperties`, and profiler metadata.
2. Use `gpu_specs.yaml.products` to map product name to chip and architecture.
3. Use `gpu_specs.yaml.compute_capability_classes` for occupancy hard limits.
4. Use `gpu_specs.yaml.chips` for die-level cache/SM hints.
5. If a product SKU is cut-down, prefer product-level `sm_count`, `l2_cache_mb`, and memory fields over chip-level values.

## Fields that directly change profile interpretation

- `sm_count`: converts grid size into blocks per SM and waves per SM.
- `max_resident_blocks_per_sm`: tells whether occupancy is blocked by architecture before resource constraints.
- `max_threads_per_sm`: upper bound for occupancy.
- `max_warps_per_sm`: expected upper bound for active warps.
- `registers_32bit_per_sm`: high register usage may lower resident blocks and warps.
- `max_shared_memory_per_sm_kb`: high shared memory may lower resident blocks.
- `max_shared_memory_per_block_kb`: dynamic shared-memory launch limit.
- `l1_shared_combined_kb`: affects L1/shared carveout interpretation.
- `l2_cache_mb`: helps interpret L2 hit rate and streaming vs reuse behavior.
- `memory_bandwidth_gbps`: normalizes DRAM throughput.
- `memory_type`: HBM vs GDDR changes expected latency/bandwidth behavior.
- `tensor_core_generation`: affects Tensor Core instruction expectations.
- `async_copy_support`: relevant for Ampere+ shared-memory staging optimization.
- `tma_support`: relevant for Hopper/Blackwell tensor memory accelerator flows.
- `wgmma_support`: relevant for Hopper/Blackwell warp-group matrix instructions.

## Profiling cautions

- Do not assume product-level cache equals full-chip cache. Many consumer SKUs disable parts of the chip.
- Do not treat high occupancy as automatically good. The profile must tie occupancy to latency hiding, eligible warps, and issue rate.
- Do not compare throughput percentages across architectures without checking clock, memory bandwidth, ECC/MIG/MPS, power limit, and profiler version.
- For Blackwell and newer architectures, prefer profiler section field names over hard-coded metric names because metric naming evolves.

## Vendor portability

For non-NVIDIA backends, keep the same schema shape where possible:

- `sm` => compute unit / Xe-core / tile / engine
- `warp` => wavefront / subgroup / SIMD group
- `shared memory` => LDS / SLM / scratchpad
- `L1/TEX` => L0/L1 data cache or texture cache equivalent
- `L2` => shared last-level GPU cache
- `Tensor Core` => matrix core / XMX / MFMA / AI engine
