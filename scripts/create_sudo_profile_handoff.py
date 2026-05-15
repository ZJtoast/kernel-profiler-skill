#!/usr/bin/env python3
"""Create a manual sudo profiling handoff script.

The generated shell script is meant to be executed by an operator as a single
privileged run, e.g. `sudo bash run_profile_with_sudo.sh`. It also self-reexecs
through sudo when launched without privileges from an interactive terminal.
The collector is then called without per-command sudo.
"""
from __future__ import annotations
import argparse
import shlex
from pathlib import Path


def q(value: str) -> str:
    return shlex.quote(value)


def main() -> int:
    ap = argparse.ArgumentParser(description="Create a sudo handoff script for kernel profiling.")
    ap.add_argument("--target-cmd", required=True, help="Executable command with arguments, e.g. './app --n 1'")
    ap.add_argument("--kernel-name", required=True, help="Human-readable kernel label")
    ap.add_argument("--kernel-regex", required=True, help="Nsight Compute regex filter without regex: prefix")
    ap.add_argument("--output-dir", required=True, help="Profile output directory")
    ap.add_argument("--launch-skip", default="10")
    ap.add_argument("--launch-count", default="1")
    ap.add_argument("--devices", default="")
    ap.add_argument("--full", action="store_true")
    ap.add_argument("--no-source", action="store_true")
    ap.add_argument("--extra", default="")
    ap.add_argument("--runtime", default="native", choices=["native", "python", "python-triton"])
    ap.add_argument("--nvtx-range", default="")
    ap.add_argument("--collector", default="scripts/ncu_collect_kernel_profile.sh", help="Path to ncu_collect_kernel_profile.sh from the execution directory")
    ap.add_argument("--script", required=True, help="Output shell script path")
    ns = ap.parse_args()

    script_path = Path(ns.script)
    script_path.parent.mkdir(parents=True, exist_ok=True)

    args = [
        q(ns.collector),
        "--target-cmd", q(ns.target_cmd),
        "--kernel-name", q(ns.kernel_name),
        "--kernel-regex", q(ns.kernel_regex),
        "--output-dir", q(ns.output_dir),
        "--launch-skip", q(ns.launch_skip),
        "--launch-count", q(ns.launch_count),
        "--runtime", q(ns.runtime),
    ]
    if ns.devices:
        args.extend(["--devices", q(ns.devices)])
    if ns.full:
        args.append("--full")
    if ns.no_source:
        args.append("--no-source")
    if ns.nvtx_range:
        args.extend(["--nvtx-range", q(ns.nvtx_range)])
    if ns.extra:
        args.extend(["--extra", q(ns.extra)])

    content = f"""#!/usr/bin/env bash
set -euo pipefail

# Manual privileged profiler run.
# Run this script as:
#   sudo bash {script_path.name}
#
# If launched without sudo from an interactive terminal, it re-executes itself
# through sudo once. The profiler commands inside the script are not prefixed
# one by one with sudo. No password is stored or echoed.

if [[ "${{EUID:-$(id -u)}}" != "0" ]]; then
  echo "Re-executing this script with sudo. The password prompt belongs to sudo."
  exec sudo bash "$0" "$@"
fi

cd "$(dirname "$0")/../.." 2>/dev/null || true
mkdir -p {q(ns.output_dir)}

echo "Running privileged Nsight Compute collection."
echo "Target command: {ns.target_cmd}"
echo "Kernel regex: {ns.kernel_regex}"
echo "Output directory: {ns.output_dir}"
echo

{' '.join(args)}

echo
echo "Profile artifacts written to: {ns.output_dir}"
"""
    script_path.write_text(content, encoding="utf-8")
    script_path.chmod(0o755)
    print(f"Wrote {script_path}")
    print("Run it manually in an interactive terminal:")
    print(f"  sudo bash {script_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
