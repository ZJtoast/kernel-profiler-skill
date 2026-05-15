# Kernel Profile Report

## 1. Target Summary

| Field | Value |
|---|---|
| Runtime |  |
| Executable |  |
| Working directory |  |
| Arguments |  |
| Kernel name / hint |  |
| Kernel filter mode |  |
| Kernel filter |  |
| Profile ID |  |
| Backend |  |
| Profiler version |  |
| GPU |  |
| Driver / runtime |  |
| Python/Triton entry |  |
| JIT/autotune policy |  |
| Privilege mode |  |

## 2. Commands

```bash
# Paste exact commands used here.
```

## 3. Collected Artifacts

| Artifact | Path | Status |
|---|---|---|
| Basic report | details/01_basic.* |  |
| SpeedOfLight report | details/02_speed_of_light.* |  |
| Memory report | details/03_memory.* |  |
| Compute report | details/04_compute.* |  |
| Occupancy/launch report | details/05_occupancy_launch.* |  |
| Roofline report | details/06_roofline.* |  |
| Source report | details/07_source.* |  |
| Metrics summary | details/metrics_summary.json |  |
| Source hotspots | details/source_hotspots.csv |  |
| Regression report | comparison/regression_report.md | optional |

## 4. Bottleneck Classification

| Bottleneck class | Confidence | Primary evidence | Status |
|---|---|---|---|
| Memory bandwidth |  |  |  |
| Compute pipeline |  |  |  |
| Occupancy/resource |  |  |  |
| Latency/scheduler |  |  |  |
| Synchronization |  |  |  |
| Roofline model |  |  |  |

## 5. Key Metrics

| Metric | Value | Interpretation |
|---|---:|---|
| Duration |  |  |
| SM throughput |  |  |
| Memory throughput |  |  |
| DRAM throughput |  |  |
| L2 hit rate |  |  |
| L1/TEX hit rate |  |  |
| Theoretical occupancy |  |  |
| Achieved occupancy |  |  |
| Registers per thread |  |  |
| Static shared memory |  |  |
| Dynamic shared memory |  |  |
| IPC |  |  |

## 6. Source / SASS / PTX Hotspots

For Triton targets, mark source mapping as one of: `reliable_python_line`, `generated_isa_only`, or `unavailable`. Do not claim Python/Triton line-level attribution unless the profiler output contains a reliable file/line association.


| Source | Line | SASS/PTX | Metric / Stall | Evidence | Confidence |
|---|---:|---|---|---|---|
|  |  |  |  |  |  |

Reference artifact: `details/source_hotspots.csv`.

## 7. Optimization Hypotheses

| Hypothesis | Evidence | Expected metric movement | Risk | Next verification |
|---|---|---|---|---|
|  |  |  |  |  |

## 8. Regression Summary

Fill only when regression mode is enabled.

| Metric | Baseline | Current | Delta | Delta % | Judgment |
|---|---:|---:|---:|---:|---|
|  |  |  |  |  |  |

Default tolerance: ±2% normal random variation.

## 9. Limitations

- 

## 10. Next Actions

1. 
2. 
3. 
