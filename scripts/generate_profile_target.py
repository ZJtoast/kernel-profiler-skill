#!/usr/bin/env python3
"""Generate profile-target.yaml from a compact kernel profiling request.

The generator resolves request-level defaults without doing a separate discovery pass.
By default, the kernel name is used directly as the profiler filter hint. Discovery is
reserved for cases where no kernel name/hint is available or exact matching fails later.
"""
from __future__ import annotations
import argparse
import re
import shlex
import sys
from pathlib import Path

try:
    import yaml
except ImportError as exc:  # pragma: no cover
    raise SystemExit("PyYAML is required: pip install pyyaml") from exc

SUPPORTED_REQUIREMENT_KEYWORDS = {
    "triton": ("target", "runtime", "python-triton"),
    "python triton": ("target", "runtime", "python-triton"),
    "triton kernel": ("target", "runtime", "python-triton"),
    "autotune": ("runtime_options", "triton_autotune_policy", "warmup_or_fixed_config"),
    "jit": ("runtime_options", "jit_warmup_required", True),
    "full": ("profiling", "initial_level", "full"),
    "basic": ("profiling", "initial_level", "basic"),
    "visual": ("visualization", "enabled", True),
    "visualization": ("visualization", "enabled", True),
    "source": ("profiling", "enable_source_mapping", True),
    "sass": ("analysis", "collect_source", "auto"),
    "ptx": ("analysis", "collect_source", "auto"),
    "roofline": ("analysis", "collect_roofline", "auto"),
    "memory": ("analysis", "collect_memory", True),
    "compute": ("analysis", "collect_compute", True),
    "occupancy": ("analysis", "collect_occupancy", True),
    "regression": ("analysis", "enable_regression_compare", True),
    "compare": ("analysis", "enable_regression_compare", True),
    "no sudo": ("privilege", "mode", "none"),
    "without sudo": ("privilege", "mode", "none"),
    "full sudo": ("privilege", "mode", "full_sudo"),
    "sudo": ("privilege", "mode", "full_sudo"),
}

UNSUPPORTED_HINTS = [
    "end-to-end", "nsys", "cpu timeline", "dataloader", "network", "mpi communication",
    "communication overlap", "system trace", "power tuning", "overclock",
    "plaintext sudo", "plain text sudo", "sudo password", "save password", "store password",
]


def default_filter_from_kernel(kernel: str, mode: str) -> tuple[str, str]:
    """Return (filter_mode, filter) for a kernel hint.

    The default is regex with an escaped kernel string. This is accepted by Nsight Compute
    as a demangled kernel-name filter and avoids a separate discovery step for common use.
    """
    if mode != "auto":
        return mode, kernel
    return "regex", f".*{re.escape(kernel)}.*"


def template() -> dict:
    return {
        "schema_version": 3.0,
        "target": {
            "runtime": "native",  # native | python | python-triton
            "executable": "./app",
            "working_directory": ".",
            "args": [],
            "env": {},
            "stdin": None,
            "timeout_seconds": None,
            "python": {
                "interpreter": "python3",
                "entry_kind": None,  # script | module | command | null
                "script": None,
                "module": None,
                "jit_framework": None,
            },
        },
        "runtime_options": {
            "triton_enabled": False,
            "triton_kernel_hint": None,
            "triton_autotune_policy": "warmup_or_fixed_config",
            "jit_warmup_required": False,
            "recommended_warmup_skip": 20,
            "require_cuda_synchronize_around_profile_window": True,
            "source_mapping_expectation": "best_effort",
            "notes": [],
        },
        "kernel": {
            "name": None,
            "filter_mode": "regex",
            "filter": None,
            "profile_id": "auto",
            "nvtx_range": None,
            "allow_discovery_fallback": True,
        },
        "profiling": {
            "backend": "nvidia-ncu",
            "initial_level": "basic",
            "warmup_policy": "auto",
            "warmup_skip": None,
            "launch_count": None,
            "enable_source_mapping": True,
            "enable_visual_report": False,
            "extra_profiler_options": [],
            "ncu_bin": "ncu",
            "output_root": "./profile",
        },
        "privilege": {
            "mode": "none",  # none | full_sudo
            "full_sudo_policy": "root-or-exact-ncu-path-nopasswd-only",
            "password_storage": "forbidden",
            "forbidden": [
                "Do not store sudo passwords in target files, scripts, logs, reports, environment variables, shell history, or commands.",
                "Do not pipe passwords into sudo, auto-type passwords, or read passwords from files.",
                "Do not use privilege for anything outside the profiling command path.",
            ],
        },
        "discovery": {
            "enabled_when_filter_missing": True,
            "fallback_when_kernel_filter_misses": True,
            "max_candidates": 20,
            "prefer_user_named_kernel": True,
            "rank_by": ["user_hint", "duration", "launch_count"],
            "command_extra_options": [],
        },
        "analysis": {
            "collect_memory": "auto",
            "collect_compute": "auto",
            "collect_occupancy": "auto",
            "collect_roofline": "auto",
            "collect_source": "auto",
            "enable_bottleneck_decision_engine": False,
            "enable_regression_compare": False,
            "compare_baseline": "auto",
            "random_variation_tolerance_pct": 2.0,
            "generate_source_hotspots_table": True,
        },
        "visualization": {
            "enabled": False,
            "format": "png",
            "require_python_packages": ["pandas", "matplotlib", "pyyaml"],
        },
        "notes": {
            "user_requirements": "",
            "unsupported_or_deferred_requirements": [],
        },
    }


def set_nested(d: dict, section: str, key: str, value):
    d[section][key] = value


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--executable", default="./app")
    ap.add_argument("--runtime", default="auto", choices=["auto", "native", "python", "python-triton"], help="Target runtime. 'python-triton' enables Triton-specific profiling defaults.")
    ap.add_argument("--python-script", default=None, help="Python script entry. Sets executable to python3 unless --executable overrides it.")
    ap.add_argument("--python-module", default=None, help="Python module entry, executed as python -m <module>.")
    ap.add_argument("--target-cmd", default=None, help="Full target command string; overrides --executable/--args when provided")
    ap.add_argument("--args", nargs="*", default=[])
    ap.add_argument("--workdir", default=".")
    ap.add_argument("--kernel", required=True, help="Kernel name or user hint")
    ap.add_argument("--filter-mode", default="auto", choices=["auto", "exact", "regex", "kernel-id", "nvtx-range", "vendor-specific", "none"])
    ap.add_argument("--filter", default=None)
    ap.add_argument("--requirement", action="append", default=[], help="Extra natural-language requirement; may be repeated")
    ap.add_argument("--privilege-mode", default=None, choices=["none", "full_sudo"])
    ap.add_argument("--ncu-bin", default=None, help="Exact Nsight Compute CLI path for the CUDA environment to profile with.")
    ap.add_argument("--output", default="profile-target.yaml")
    ns = ap.parse_args()

    cfg = template()
    # Resolve target command. Full --target-cmd remains the most precise option.
    if ns.target_cmd:
        parts = shlex.split(ns.target_cmd)
        if not parts:
            raise SystemExit("--target-cmd cannot be empty")
        cfg["target"]["executable"] = parts[0]
        cfg["target"]["args"] = parts[1:]
        if any(part.endswith(".py") for part in parts[:2]) or parts[0].startswith("python"):
            cfg["target"]["runtime"] = "python"
            cfg["target"]["python"]["interpreter"] = parts[0]
            cfg["target"]["python"]["entry_kind"] = "command"
            for part in parts[1:]:
                if part.endswith(".py"):
                    cfg["target"]["python"]["script"] = part
                    break
    elif ns.python_script:
        cfg["target"]["executable"] = ns.executable if ns.executable != "./app" else "python3"
        cfg["target"]["args"] = [ns.python_script, *ns.args]
        cfg["target"]["runtime"] = "python"
        cfg["target"]["python"]["interpreter"] = cfg["target"]["executable"]
        cfg["target"]["python"]["entry_kind"] = "script"
        cfg["target"]["python"]["script"] = ns.python_script
    elif ns.python_module:
        cfg["target"]["executable"] = ns.executable if ns.executable != "./app" else "python3"
        cfg["target"]["args"] = ["-m", ns.python_module, *ns.args]
        cfg["target"]["runtime"] = "python"
        cfg["target"]["python"]["interpreter"] = cfg["target"]["executable"]
        cfg["target"]["python"]["entry_kind"] = "module"
        cfg["target"]["python"]["module"] = ns.python_module
    else:
        cfg["target"]["executable"] = ns.executable
        cfg["target"]["args"] = ns.args
    cfg["target"]["working_directory"] = ns.workdir
    cfg["kernel"]["name"] = ns.kernel

    if ns.runtime != "auto":
        cfg["target"]["runtime"] = ns.runtime
    elif ns.python_script or ns.python_module:
        cfg["target"]["runtime"] = "python"

    if ns.filter:
        cfg["kernel"]["filter_mode"] = "regex" if ns.filter_mode == "auto" else ns.filter_mode
        cfg["kernel"]["filter"] = ns.filter
    elif ns.filter_mode == "none":
        cfg["kernel"]["filter_mode"] = "auto"
        cfg["kernel"]["filter"] = None
    else:
        mode, filt = default_filter_from_kernel(ns.kernel, ns.filter_mode)
        cfg["kernel"]["filter_mode"] = mode
        cfg["kernel"]["filter"] = filt

    requirements = " ".join(ns.requirement).strip()
    cfg["notes"]["user_requirements"] = requirements
    lower = requirements.lower()
    for key, action in SUPPORTED_REQUIREMENT_KEYWORDS.items():
        if key in lower:
            set_nested(cfg, *action)
    if cfg["target"].get("runtime") == "python-triton":
        cfg["target"]["python"]["jit_framework"] = "triton"
        cfg["runtime_options"]["triton_enabled"] = True
        cfg["runtime_options"]["triton_kernel_hint"] = ns.kernel
        cfg["runtime_options"]["jit_warmup_required"] = True
        if cfg["profiling"].get("warmup_skip") is None:
            cfg["profiling"]["warmup_skip"] = 20
        if cfg["profiling"].get("launch_count") is None:
            cfg["profiling"]["launch_count"] = 1
        cfg["runtime_options"]["notes"].append(
            "For Triton, warm up JIT/autotune before the profiled launch window. If autotune is enabled, prefer a fixed config or skip autotune launches."
        )
        cfg["runtime_options"]["notes"].append(
            "Nsight Compute profiles the generated GPU kernel launched by the Python process; source mapping to Python/Triton code is best effort."
        )
    if cfg["visualization"].get("enabled"):
        cfg["profiling"]["enable_visual_report"] = True
    if ns.privilege_mode:
        cfg["privilege"]["mode"] = ns.privilege_mode
    if ns.ncu_bin:
        cfg["profiling"]["ncu_bin"] = ns.ncu_bin

    for hint in UNSUPPORTED_HINTS:
        if hint in lower:
            cfg["notes"]["unsupported_or_deferred_requirements"].append(
                f"'{hint}' is unsupported or outside kernel-only profiling scope. Plaintext sudo password storage is not supported."
            )

    out = Path(ns.output)
    out.write_text(yaml.safe_dump(cfg, sort_keys=False, allow_unicode=True), encoding="utf-8")
    print(f"Wrote {out}")
    print(f"Kernel filter: {cfg['kernel']['filter_mode']}:{cfg['kernel']['filter']}")
    print(f"Privilege mode: {cfg['privilege']['mode']}")
    if cfg["notes"]["unsupported_or_deferred_requirements"]:
        print("Unsupported/deferred requirements detected:", file=sys.stderr)
        for item in cfg["notes"]["unsupported_or_deferred_requirements"]:
            print(f"- {item}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
