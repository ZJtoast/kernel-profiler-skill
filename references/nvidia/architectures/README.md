# NVIDIA Architecture Reference Index

This folder replaces the old monolithic `references/nvidia/nvidia-gpu-architectures.md` file.

Use this folder in two ways:

1. **Machine-readable lookup**: `gpu_specs.yaml` contains architecture, chip, product, memory, cache, SM, occupancy, and profiling-relevant fields.
2. **Human-readable interpretation**: `architecture-notes.md` explains how the fields affect kernel profiling decisions.

The database intentionally separates:

- `compute_capability_classes`: CUDA architectural limits by compute capability.
- `architectures`: generation-level properties.
- `chips`: die-level properties such as full SM count and cache where available.
- `products`: shipping GPU SKUs, which may be cut-down versions of chips.
- `profile_implications`: how agents should use these fields during kernel analysis.

Values marked `null` mean the public source was not specific enough. Do not infer missing values unless the profiler or device API confirms them at runtime.
