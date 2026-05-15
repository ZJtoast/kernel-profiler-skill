# Notice

Kernel Profiler Skill contains normalized profiling workflow notes and templates. The default NVIDIA backend references public NVIDIA Nsight Compute documentation and the public `slowlyC/agent-gpu-skills` repository structure.

This package does not include verbatim copies of NVIDIA manuals. If a downstream distribution copies upstream documentation into `references/`, preserve the upstream copyright and license notices.

Referenced upstream materials:

- NVIDIA Nsight Compute documentation: https://docs.nvidia.com/nsight-compute/
- NVIDIA Nsight Compute Profiling Guide: https://docs.nvidia.com/nsight-compute/ProfilingGuide/
- NVIDIA Nsight Compute CLI Guide: https://docs.nvidia.com/nsight-compute/NsightComputeCli/
- slowlyC/agent-gpu-skills: https://github.com/slowlyC/agent-gpu-skills
- slowlyC cuda_skill references/ncu-guide.md
- slowlyC cuda_skill references/ncu-docs/ProfilingGuide.md

## v3 Architecture Reference Change

The previous monolithic `references/nvidia/nvidia-gpu-architectures.md` file has been removed.
Architecture and product specifications now live under `references/nvidia/architectures/`, with
`gpu_specs.yaml` as the machine-readable hardware database.

Static hardware values are best-effort public-reference data. Runtime profiler and device metadata
must override the static database in all final reports.
