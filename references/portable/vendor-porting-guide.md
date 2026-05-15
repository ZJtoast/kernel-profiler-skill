# Vendor Porting Guide

This skill uses a stable workflow and a replaceable profiler backend. Porting to another GPU vendor means preserving the workflow contract while replacing commands, section names, metric names, and architecture references.

## Stable Files

Do not change these unless the workflow itself changes:

```text
SKILL.md
README.md
assets/templates/profile-target.yaml
assets/templates/final_report_template.md
assets/templates/run_manifest_template.yaml
references/portable/portable-bottleneck-taxonomy.md
references/portable/metric-aliases.yaml
```

## Vendor-Specific Files

Add or edit:

```text
references/<vendor>/<vendor>-architecture.md
references/<vendor>/<vendor>-profiler-guide.md
references/<vendor>/<vendor>-metric-map.md
references/<vendor>/vendor-adapter-<backend>.yaml
```

## Required Backend Operations

Each backend must implement:

```yaml
backend_contract:
  version_command: []
  list_sections_command: []
  discover_kernels_command: []
  profile_basic: []
  profile_speed_of_light: []
  profile_memory: []
  profile_compute: []
  profile_occupancy: []
  profile_roofline: []
  profile_source: []
  export_raw_metrics: []
  report_extension: ""
  metric_dictionary: "references/<vendor>/<vendor>-metric-map.md"
```

If the vendor profiler has no direct equivalent for a phase, implement the closest available collection and document limitations.

## Portable Concepts

Map these concepts first:

| Portable concept | Required explanation in vendor map |
|---|---|
| compute throughput | How close compute units are to peak execution throughput |
| memory throughput | How close memory hierarchy or device memory is to peak bandwidth |
| compute unit occupancy | How much resident work exists on a compute unit |
| scheduler health | Whether schedulers have eligible work to issue |
| memory coalescing | Whether adjacent lanes form efficient memory transactions |
| local scratch spill | Whether private/local memory traffic indicates register spills |
| on-chip scratch conflict | Whether shared/LDS/SLM accesses serialize due to banking |
| instruction mix | Which ISA classes dominate execution |
| roofline | Arithmetic intensity vs attainable performance |
| source attribution | Mapping metrics to source and ISA locations |
| JIT kernel attribution | Mapping generated GPU kernel names back to framework-level kernel hints when possible |

## Report Compatibility

Final reports must retain the same section names and table shapes. Vendor-specific terms can appear in parentheses:

```text
compute unit occupancy (NVIDIA SM occupancy)
on-chip scratch conflict (AMD LDS bank conflict)
source/ISA attribution (Intel source/Xe ISA)
```

## Porting Checklist

- [ ] Backend version command works.
- [ ] Kernel filter method supports exact name or regex.
- [ ] Launch-window controls exist or equivalent workaround is documented.
- [ ] Basic pass collects launch, occupancy, compute, and memory summary.
- [ ] High-level throughput pass exists.
- [ ] Memory pass can expose cache/bandwidth/coalescing/scratch evidence.
- [ ] Compute pass can expose pipeline/instruction mix evidence.
- [ ] Occupancy/scheduler pass can expose resident work and stall evidence.
- [ ] Roofline pass exists or limitations are documented.
- [ ] Source/ISA correlation exists or limitations are documented.
- [ ] Python process targets are supported, or limitations are documented.
- [ ] JIT-generated kernel targets such as Triton are supported, or limitations are documented.
- [ ] Raw metrics can be exported for visualization.
- [ ] Metric aliases are mapped.
- [ ] Architecture document covers execution model and memory hierarchy.
