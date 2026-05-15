<div align="center">

# 🚀 Kernel Profiler Skill

**面向 CUDA 与 Triton Kernel 的标准化 GPU Profiling 工作流**

`Nsight Compute` · `CUDA` · `Triton` · `源码/SASS/PTX 归因` · `回归对比` · `可迁移 Backend`

</div>

---

## 项目定位

Kernel Profiler Skill 用于分析单个 GPU kernel 或一组高度相关的 kernel。它关注的是 kernel 级问题：launch 配置、occupancy、memory hierarchy、compute pipeline、warp stall、instruction mix、source/SASS/PTX 热点和优化前后回归对比。

默认 profiler backend 是 NVIDIA Nsight Compute (`ncu`)。backend、metric alias 和 GPU 架构数据库是分离的，因此可以迁移到其他厂商 profiler。

支持目标包括：

- 原生 CUDA 可执行文件；
- benchmark 命令；
- 会发射 CUDA kernel 的 Python 进程；
- Python 中启动的 Triton JIT kernel。

默认不处理 CPU timeline、dataloader、通信、launch gap、MPI/NCCL overlap、端到端系统 trace 和系统调度问题。这些属于 system profiler 的范围。

## 安装方式

clone 这个仓库，或在当前目录运行下面的复制命令：

```bash
# Linux/macOS
mkdir -p ~/.codex/skills/kernel-profiler-skill
cp -R . ~/.codex/skills/kernel-profiler-skill/

# Windows PowerShell
New-Item -ItemType Directory -Force "$env:USERPROFILE\.codex\skills\kernel-profiler-skill"
Copy-Item -Recurse -Force . "$env:USERPROFILE\.codex\skills\kernel-profiler-skill"
```

重启或 reload Codex 后，打开你要 profile 的 CUDA/Triton 项目，再用 `/skill kernel-profiler-skill` 调用；skill 本体从 `~/.codex/skills/kernel-profiler-skill` 加载。

## 使用方式：从自然语言请求开始

在 coding agent 中给出简短请求，例如：

```text
/skill kernel-profiler-skill，帮我 profile 一下 hgemm_byzj_v0 这个 kernel，要可视化报告
```

执行的流程：

1. 解析请求：kernel hint 为 `hgemm_byzj_v0`，开启可视化，默认 profile level 为 `basic`，默认 backend 为 `nvidia-ncu`。
2. 如果请求没有给出可执行文件或命令，从当前仓库中解析 benchmark 入口，例如 `README`、`CMakeLists.txt`、`Makefile`、`build/`、`bin/`、`examples/`、benchmark 脚本和 run 脚本。
3. 调用 `scripts/generate_profile_target.py` 生成 `profile-target.yaml`。
4. 直接用 kernel 名称生成初始 filter。`hgemm_byzj_v0` 默认生成 `.*hgemm_byzj_v0.*`。
5. 运行分阶段 profile、抽取指标、生成 source hotspot，并在需要时生成可视化报告。
6. 最终产物写入 `./profile/<kernel_name>_<profile_id>/`。

手动方式仍然支持：可以从 `assets/templates/profile-target.yaml` 手写 target，也可以生成后手动修改，或直接调用底层脚本。

当 agent 已经解析出 benchmark 命令后，对上面请求通常会生成类似命令：

```bash
python3 scripts/generate_profile_target.py \
  --target-cmd "./build/bench_gemm --m 4096 --n 4096 --k 4096 --iters 100" \
  --kernel hgemm_byzj_v0 \
  --requirement "visual report" \
  --output profile-target.yaml
```

生成的 kernel 部分应类似：

```yaml
kernel:
  name: hgemm_byzj_v0
  filter_mode: regex
  filter: .*hgemm_byzj_v0.*
  allow_discovery_fallback: true
```

Discovery 只作为 fallback：没有 kernel 名称、过滤失败或过滤结果有歧义时才使用。

## 功能概览

### Target 文件生成

一次 profile 由 `profile-target.yaml` 描述。可以从 `assets/templates/profile-target.yaml` 手写，也可以用脚本生成。

生成器支持：

- native executable；
- Python/Triton 命令；
- kernel 名称提示；
- 根据 kernel 名称自动生成 regex filter；
- 可视化报告选项；
- source/SASS/PTX 选项；
- Roofline 选项；
- before/after regression 选项；
- 不支持需求记录。

指定 kernel 名称时，默认直接使用该名称生成过滤条件：

```yaml
kernel:
  name: hgemm_byzj_v0
  filter_mode: regex
  filter: .*hgemm_byzj_v0.*
  allow_discovery_fallback: true
```

Discovery 只在没有 kernel 名称、过滤失败或过滤结果歧义时使用。

### 分阶段 Nsight Compute 采集

标准 profile 阶段包括：

1. `basic`：快速检查 launch、occupancy 和高层利用率。
2. `SpeedOfLight`：判断 compute 方向还是 memory 方向。
3. `MemoryWorkloadAnalysis`：分析 DRAM、L1/TEX、L2、transaction、sector、shared memory conflict、local memory 等。
4. `ComputeWorkloadAnalysis` + `InstructionStats`：分析 pipeline、IPC、instruction mix、Tensor Core、FP/INT/SFU/LDST 等。
5. `LaunchStats` + `Occupancy` + scheduler/warp state：分析 active warps、resident blocks、register/shared-memory 限制和 stall reason。
6. `Roofline`：backend 支持时采集。
7. `SourceCounters`：支持时做 source/SASS/PTX 归因。

原始数据保存在 `details/`，最终报告保持规范化和可读性。

### Triton Kernel Profiling

Triton kernel 通过启动它的 Python 进程进行 profile。分析对象是 JIT 生成并 launch 到 GPU 上的 kernel，而不是 Python 函数运行时间。

Triton 支持包括：

- Python 命令 target；
- JIT warmup；
- autotune 污染控制；
- 默认更大的 launch-skip；
- Python/Triton source mapping 的 best-effort 标记；
- Python 函数名和真实 GPU kernel 名不一致时 fallback discovery。

最终证据采集建议固定 Triton config，并跳过 JIT/autotune/warmup launch。

### 权限处理

部分 profiler counter 需要更高权限。支持三种模式：

| 模式                   | 说明                                                                    |
| ---------------------- | ----------------------------------------------------------------------- |
| `none`               | 不使用 sudo。                                                           |
| `authorized_sudo`    | 仅在 root、sudo 已缓存或 sudoers 已配置窄范围 `NOPASSWD` 时直接运行。 |
| `manual_sudo_script` | 生成脚本，由操作者用 `sudo bash ...` 整体运行。                       |

不实现明文 sudo 密码保存。密码不得进入 YAML、脚本、日志、环境变量、shell history、命令或报告。

### 指标抽取

大 CSV 会先压缩成机器可读摘要：

```text
details/metrics_summary.json
details/metrics_extracted.jsonl
```

这些文件用于最终报告、回归对比和可选规则判断。

### Source Hotspot 表

标准热点表：

```text
details/source_hotspots.csv
```

字段：

```text
source_file,line,function,sass_opcode,ptx_opcode,metric,value,stall_reason,bottleneck_class,confidence,evidence
```

每个主要瓶颈都应尽量关联到源码行、SASS/PTX 指令族，或说明为什么无法关联。

### 可选 Bottleneck Decision Engine

默认关闭。规则位于：

```text
references/portable/rules/bottleneck_rules.yaml
```

该结果只作为辅助判断，最终结论仍需要具体 metric 和 hotspot 证据。

### 可选 Before/After Regression

默认关闭。启用后可以和指定 baseline 或同 kernel 前缀的最近历史 profile 对比。

报告包含：baseline 值、current 值、绝对变化、百分比变化、metric 级判断、整体 verdict、缺失数据说明、lower-is-better/higher-is-better 语义和默认 `±2%` 随机波动区间。

### 可选可视化报告

可根据 `final_report.md` 和 `details/` 生成图片报告。缺失 Python 包时应输出安装建议，而不是生成不完整图片。

### Vendor Portability

NVIDIA backend 位于：

```text
references/nvidia/vendor-adapter-nvidia-ncu.yaml
```

通用 taxonomy、metric aliases 和迁移说明位于：

```text
references/portable/
```

迁移到其他厂商时，需要替换 discovery、filter、profile stage、raw metric export、source/ISA correlation 和 metric alias。

## 目录结构

```text
kernel-profiler-skill/
├── SKILL.md
├── README.md
├── README.zh-CN.md
├── docs/
├── references/
├── scripts/
└── assets/
```

关键路径：

```text
assets/templates/profile-target.yaml
assets/templates/final_report_template.md
assets/templates/run_manifest_template.yaml
assets/examples/profile-target.example.yaml
assets/examples/profile-target.triton.example.yaml

docs/workload-stabilization-guide.md
docs/triton-kernel-profiling.md
docs/vendor-conformance.md
docs/legal/NOTICE.md

references/nvidia/architectures/gpu_specs.yaml
references/nvidia/ncu-guide.md
references/nvidia/profilingguide.md
references/nvidia/ncu-metric-map.md
references/nvidia/vendor-adapter-nvidia-ncu.yaml
references/portable/metric-aliases.yaml
references/portable/portable-bottleneck-taxonomy.md
references/portable/vendor-porting-guide.md
references/portable/rules/bottleneck_rules.yaml

scripts/generate_profile_target.py
scripts/ncu_collect_kernel_profile.sh
scripts/discover_kernels.sh
scripts/create_sudo_profile_handoff.py
scripts/extract_ncu_metrics.py
scripts/generate_source_hotspots.py
scripts/bottleneck_decision_engine.py
scripts/compare_profiles.py
scripts/visualize_profile_report.py
scripts/vendor_conformance_check.py
```

## `profile-target.yaml` 参数说明

`profile-target.yaml` 是自然语言请求、采集脚本和最终报告之间的标准化契约。正常流程中它由 agent 自动生成，但字段保持可读，方便必要时手动修改。

### `schema_version`

schema 版本号，当前为 `3.0`。

### `target`

描述启动 kernel 的命令。

| 字段                     | 含义                       | 常见值                                        |
| ------------------------ | -------------------------- | --------------------------------------------- |
| `runtime`              | 运行时类型                 | `native`、`python`、`python-triton`     |
| `executable`           | 要执行的程序               | `./build/bench_gemm`、`python3`           |
| `working_directory`    | 执行命令时的工作目录       | `.`                                         |
| `args`                 | 传给 executable 的参数数组 | `['--m', '4096']`                           |
| `env`                  | 运行时环境变量             | `{CUDA_VISIBLE_DEVICES: '0'}`               |
| `stdin`                | 可选 stdin 输入            | `null`                                      |
| `timeout_seconds`      | 可选超时时间               | `null` 或整数                               |
| `python.interpreter`   | Python 解释器              | `python3`                                   |
| `python.entry_kind`    | Python 入口类型            | `script`、`module`、`command`、`null` |
| `python.script`        | Python 脚本路径            | `bench_triton_hgemm.py`                     |
| `python.module`        | `python -m` 模块名       | `package.bench`                             |
| `python.jit_framework` | JIT 框架标记               | Triton 场景为 `triton`                      |

### `runtime_options`

运行时相关选项，主要用于 Python/Triton。

| 字段                                               | 含义                                                                 |
| -------------------------------------------------- | -------------------------------------------------------------------- |
| `triton_enabled`                                 | 开启 Triton 相关稳定性和报告说明。                                   |
| `triton_kernel_hint`                             | 请求中给出的 Triton kernel/function 名称提示。                       |
| `triton_autotune_policy`                         | `fixed_config`、`warmup_or_fixed_config` 或 `allow_autotune`。 |
| `jit_warmup_required`                            | 标记 JIT warmup 是否需要在正式采集前完成。                           |
| `recommended_warmup_skip`                        | JIT/autotune/warmup 建议跳过的 launch 数量。                         |
| `require_cuda_synchronize_around_profile_window` | 建议 benchmark/profile 区间前后显式同步。                            |
| `source_mapping_expectation`                     | source 映射预期，Triton 通常是 `best_effort`。                     |
| `notes`                                          | runtime 相关注意事项，会进入报告。                                   |

### `kernel`

选择被 profile 的 kernel。

| 字段                         | 含义                                                                                   |
| ---------------------------- | -------------------------------------------------------------------------------------- |
| `name`                     | 请求中的 kernel 标签。                                                                 |
| `filter_mode`              | `exact`、`regex`、`kernel-id`、`nvtx-range`、`vendor-specific` 或 `auto`。 |
| `filter`                   | backend 过滤条件；命名 kernel 默认是 `.*<kernel_name>.*`。                           |
| `profile_id`               | 输出目录标识；`auto` 会根据 kernel 名和时间生成。                                    |
| `nvtx_range`               | 可选 NVTX range 过滤。                                                                 |
| `allow_discovery_fallback` | 仅当初始 filter 缺失、失败或歧义时允许 discovery。                                     |

### `profiling`

控制采集深度和输出位置。

| 字段                       | 含义                                    |
| -------------------------- | --------------------------------------- |
| `backend`                | profiler backend，默认 `nvidia-ncu`。 |
| `initial_level`          | `basic` 或 `full`，默认 `basic`。 |
| `warmup_policy`          | `auto`、`fixed` 或 `none`。       |
| `warmup_skip`            | 正式采集前跳过的匹配 launch 数。        |
| `launch_count`           | 采集的匹配 launch 数。                  |
| `enable_source_mapping`  | 可用时开启 source/SASS/PTX 归因。       |
| `enable_visual_report`   | 开启可视化报告。                        |
| `extra_profiler_options` | backend-specific 额外参数。             |
| `output_root`            | profile 输出根目录。                    |

### `privilege`

定义 profiler 权限策略。

| 字段                                | 含义                                                                |
| ----------------------------------- | ------------------------------------------------------------------- |
| `mode`                            | `none`、`authorized_sudo` 或 `manual_sudo_script`。           |
| `authorized_sudo_policy`          | 限制 direct sudo 只能用于 root、cached sudo 或窄范围 `NOPASSWD`。 |
| `generate_manual_sudo_handoff`    | 允许生成 `run_profile_with_sudo.sh`。                             |
| `handoff_script_name`             | 手动 sudo 脚本名称。                                                |
| `allow_internal_sudo_per_command` | 必须保持 `false`，脚本整体 sudo 运行。                            |
| `password_storage`                | 必须保持 `forbidden`。                                            |
| `forbidden`                       | 密码和权限使用的禁止项。                                            |

### `discovery`

fallback kernel discovery 设置。对于已经命名的 kernel，discovery 不是默认路径。

| 字段                                   | 含义                                         |
| -------------------------------------- | -------------------------------------------- |
| `enabled_when_filter_missing`        | 没有 filter 时允许 discovery。               |
| `fallback_when_kernel_filter_misses` | 初始 filter 未匹配 kernel 时允许 discovery。 |
| `max_candidates`                     | 保留的候选 kernel 数量上限。                 |
| `prefer_user_named_kernel`           | 排序时优先使用请求中的 kernel 名称。         |
| `rank_by`                            | 候选排序键。                                 |
| `command_extra_options`              | 仅 discovery 阶段使用的额外参数。            |

### `analysis`

控制目标分析和可选分析。

| 字段                                  | 含义                                                        |
| ------------------------------------- | ----------------------------------------------------------- |
| `collect_memory`                    | memory 分析，`auto`、`true` 或 `false`。              |
| `collect_compute`                   | compute 分析，`auto`、`true` 或 `false`。             |
| `collect_occupancy`                 | occupancy/scheduler 分析，`auto`、`true` 或 `false`。 |
| `collect_roofline`                  | Roofline 分析，`auto`、`true` 或 `false`。            |
| `collect_source`                    | source/SASS/PTX 采集，`auto`、`true` 或 `false`。     |
| `enable_bottleneck_decision_engine` | 可选规则引擎，默认 `false`。                              |
| `enable_regression_compare`         | 可选 before/after 对比，默认 `false`。                    |
| `compare_baseline`                  | `auto`、显式路径或 `null`。                             |
| `random_variation_tolerance_pct`    | 回归判断默认随机波动区间，默认 `2.0`。                    |
| `generate_source_hotspots_table`    | 生成 `details/source_hotspots.csv`。                      |

### `visualization`

控制可选可视化报告。

| 字段                        | 含义                         |
| --------------------------- | ---------------------------- |
| `enabled`                 | 是否生成可视化报告。         |
| `format`                  | 图片格式，通常是 `png`。   |
| `require_python_packages` | 渲染前需要检查的 Python 包。 |

### `notes`

保留原始需求和不支持项。

| 字段                                     | 含义                                            |
| ---------------------------------------- | ----------------------------------------------- |
| `user_requirements`                    | 请求中的额外要求。                              |
| `unsupported_or_deferred_requirements` | kernel-only 范围外或当前 backend 不支持的要求。 |

## 快速开始：CUDA 可执行文件

生成 target：

```bash
python3 scripts/generate_profile_target.py \
  --target-cmd "./build/bench_gemm --m 4096 --n 4096 --k 4096 --iters 100" \
  --kernel hgemm_byzj_v0 \
  --requirement "visual report, source, roofline" \
  --output profile-target.yaml
```

执行 profile：

```bash
scripts/ncu_collect_kernel_profile.sh \
  --target-cmd "./build/bench_gemm --m 4096 --n 4096 --k 4096 --iters 100" \
  --kernel-name hgemm_byzj_v0 \
  --kernel-regex ".*hgemm_byzj_v0.*" \
  --launch-skip 10 \
  --launch-count 1 \
  --output-dir ./profile/hgemm_byzj_v0_20260515_120000
```

抽取指标：

```bash
python3 scripts/extract_ncu_metrics.py \
  --input ./profile/hgemm_byzj_v0_20260515_120000/details/metrics_raw.csv \
  --output-dir ./profile/hgemm_byzj_v0_20260515_120000/details
```

## 快速开始：Triton Kernel

生成 Triton target：

```bash
python3 scripts/generate_profile_target.py \
  --runtime python-triton \
  --target-cmd "python3 bench_triton_hgemm.py --m 4096 --n 4096 --k 4096 --iters 100" \
  --kernel hgemm_byzj_v0 \
  --requirement "triton, visual report, source, roofline" \
  --output profile-target.yaml
```

执行 profile：

```bash
scripts/ncu_collect_kernel_profile.sh \
  --runtime python-triton \
  --target-cmd "python3 bench_triton_hgemm.py --m 4096 --n 4096 --k 4096 --iters 100" \
  --kernel-name hgemm_byzj_v0 \
  --kernel-regex ".*hgemm_byzj_v0.*" \
  --launch-skip 20 \
  --launch-count 1 \
  --output-dir ./profile/hgemm_byzj_v0_20260515_120000
```

## 手动 Sudo Handoff

生成脚本：

```bash
python3 scripts/create_sudo_profile_handoff.py \
  --target-cmd "./build/bench_gemm --m 4096 --n 4096 --k 4096 --iters 100" \
  --kernel-name hgemm_byzj_v0 \
  --kernel-regex ".*hgemm_byzj_v0.*" \
  --launch-skip 10 \
  --launch-count 1 \
  --output-dir ./profile/hgemm_byzj_v0_20260515_120000 \
  --script ./profile/hgemm_byzj_v0_20260515_120000/run_profile_with_sudo.sh
```

整体 sudo 执行：

```bash
sudo bash ./profile/hgemm_byzj_v0_20260515_120000/run_profile_with_sudo.sh
```

## 输出结构

```text
profile/<kernel_name>_<profile_id>/
├── final_report.md
├── run_manifest.yaml
├── details/
│   ├── 01_basic.*
│   ├── 02_speed_of_light.*
│   ├── 03_memory.*
│   ├── 04_compute.*
│   ├── 05_occupancy_scheduler.*
│   ├── 06_roofline.*
│   ├── 07_source.*
│   ├── metrics_summary.json
│   ├── metrics_extracted.jsonl
│   └── source_hotspots.csv
├── visual/
│   └── profile_summary.png
└── comparison/
    └── regression_report.md
```

`visual/` 和 `comparison/` 只在对应功能开启时出现。

## 最终报告内容

最终报告包括 target 命令、runtime、GPU/profiler 信息、kernel filter、真实 kernel 名、launch-skip/count、basic 结论、SpeedOfLight 判断、memory 分析、compute 分析、occupancy/scheduler 分析、Roofline 结果、source/SASS/PTX hotspot、瓶颈分类、优化建议、可视化报告路径、可选回归对比和数据质量说明。

## Backend Conformance

```bash
python3 scripts/vendor_conformance_check.py \
  --adapter references/nvidia/vendor-adapter-nvidia-ncu.yaml
```

## 参考来源与署名

本项目围绕可迁移的 kernel profiling 流程设计。默认后端是 NVIDIA Nsight Compute，但 profiling 流程、指标解释和厂商命令适配层是分离的，便于其他 GPU 厂商替换 profiler backend 和 metric mapping。

### 上游官方文档

- NVIDIA Nsight Compute 官方文档  
  用于整理 Nsight Compute CLI 行为、报告结构、metric collection、section、set、源码/SASS 关联、replay mode 和 profiling workflow。

- NVIDIA CUDA C++ Programming Guide 与 CUDA Compute Capability 文档  
  用于整理 warp size、每 SM 最大 resident block、每 SM 最大 resident warp、register 数量、shared memory 上限和 occupancy 相关解释。

- NVIDIA CUDA C++ Best Practices Guide  
  用于整理 CUDA kernel 优化相关知识，例如访存合并、occupancy、arithmetic intensity、memory hierarchy 行为和性能测量方法。

### 第三方参考资料

以下文件来自或改写自开源仓库 `slowlyC/agent-gpu-skills` 中 `cuda-skill` 的 references：

- `references/nvidia/ncu-guide.md`
- `references/nvidia/profilingguide.md`

原始来源仓库：

- `https://github.com/slowlyC/agent-gpu-skills`

署名信息：

- 原始仓库：`slowlyC/agent-gpu-skills`
- 原作者 / 维护者：`slowlyC`
- 来源 skill：`cuda-skill`
- 相关上游 reference 路径包括：
  - `references/ncu-guide.md`
  - `references/ncu-docs/ProfilingGuide.md`
  - `references/best-practices-guide/`

这些文件作为 agent 查询和 workflow grounding 的参考资料包含在本项目中。如果重新分发本 skill，应保留本署名部分，并保留 `slowlyC/agent-gpu-skills` 上游许可证和 notice 要求的相关文件。

### 本地 reference 目录说明

- `references/nvidia/ncu-guide.md`  
  Nsight Compute 命令和 workflow 参考，来自 `slowlyC/agent-gpu-skills`。

- `references/nvidia/profilingguide.md`  
  Nsight Compute profiling guide 参考，来自 `slowlyC/agent-gpu-skills`。

- `references/nvidia/vendor-adapter-nvidia-ncu.yaml`  
  NVIDIA Nsight Compute backend adapter，用于把通用 profiling 流程映射到 NCU 命令、section、set 和报告产物。

- `references/nvidia/architectures/gpu_specs.yaml`  
  机器可读的 NVIDIA GPU 架构和设备参数数据库，用于架构相关的 profiling 解读。

- `references/nvidia/architectures/architecture-notes.md`  
  面向人工阅读的 NVIDIA 架构说明，用于解释不同 GPU 代际上的 kernel bottleneck。

- `references/portable/metric-aliases.yaml`  
  可迁移 metric alias 表，用于降低分析逻辑对 NVIDIA 专有 metric 名称的耦合。

- `references/portable/portable-bottleneck-taxonomy.md`  
  厂商中立的 bottleneck 分类体系，用于最终报告和可选规则分析。

- `references/portable/vendor-porting-guide.md`  
  其他 GPU 厂商替换 Nsight Compute backend 时的迁移指南。

- `references/portable/rules/bottleneck_rules.yaml`  
  可选 bottleneck decision engine 的规则文件。默认不启用。

## 更新日志

### v1.0

稳定版 kernel-only profiling package，支持 native CUDA 与 Python/Triton。包含 target 生成、分阶段 Nsight Compute 采集、可选可视化、可选 before/after regression、可选 bottleneck rules、source hotspot 抽取、sudo handoff、NVIDIA 硬件元数据、vendor-portable metric aliases 和 backend conformance check。

### v0.6

统一顶层目录为 `SKILL.md`、`README.md`、`README.zh-CN.md`、`docs/`、`references/`、`scripts/`、`assets/`。templates 与 examples 移入 `assets/`，conformance 文档移入 `docs/`。

### v0.5

明确权限模式：无 sudo、已授权 sudo、手动 sudo 脚本。kernel 名称请求默认直接生成 regex filter，discovery 只作为 fallback。

### v0.4

增加手动 sudo handoff 脚本生成，适配无法交互式输入 sudo 密码的 profiler 执行环境。

### v0.3

将 NVIDIA 架构资料改为机器可读 `gpu_specs.yaml`，并加入 target 生成、metric extraction、可选 bottleneck rules、source hotspot schema、regression comparison、workload stabilization 和 backend conformance。

### v0.2

新增中文 README，扩充 NVIDIA 架构和 Nsight Compute 参考，允许 handwritten target 中 kernel filter 为空。

### v0.1

初始 kernel-only profiling skill，默认使用 Nsight Compute，包含分阶段采集、target schema、最终报告模板、可视化脚本和 vendor portability 说明。
