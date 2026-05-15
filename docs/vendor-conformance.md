# Vendor Conformance Test

A backend adapter must support the kernel-only workflow before it can replace NVIDIA Nsight Compute.

Required capabilities:

- `can_discover_kernel`
- `can_filter_kernel`
- `can_collect_basic`
- `can_collect_memory`
- `can_collect_compute`
- `can_collect_occupancy`
- `can_collect_roofline`
- `can_export_raw_metrics`
- `can_link_source_or_isa`
- `can_compare_reports`
- `can_profile_python_process`
- `can_profile_triton_jit_kernels`

Run:

```bash
python3 scripts/vendor_conformance_check.py --adapter references/nvidia/vendor-adapter-nvidia-ncu.yaml
```
