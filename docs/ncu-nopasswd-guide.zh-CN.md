# Nsight Compute NOPASSWD 配置指南

当 `ncu` 报 `ERR_NVGPUCTRPERM`，或 agent 使用 `sudo -n ncu ...` 时提示需要密码，说明当前环境不能非交互式访问性能计数器。这个 skill 不读取、不保存、不管道传输 sudo 密码；需要为 agent 在当前 CUDA 环境中检测到的默认 `ncu` 绝对路径配置窄范围 `NOPASSWD`。

出现这种情况时，本次 profile 必须立刻停止。配置完成后，请在下一次对话中重新发起 profile。

## 1. 使用 agent 提供的 ncu 路径

触发权限错误时，collector 会先在当前环境中检测默认 `ncu`，并在提示中打印类似内容：

```text
agent 当前使用的 ncu 命令：
  ncu

agent 检测到的默认 ncu 绝对路径：
  /usr/local/cuda-12.4/bin/ncu
```

后续 sudoers 规则必须使用这条绝对路径。多 CUDA 环境服务器必须在 profile 前加载同一个 CUDA module / PATH，保证 `ncu` 仍然解析到这条路径。

如果你想手动确认，也可以在同一个 CUDA 环境中运行：

```bash
command -v ncu
readlink -f "$(command -v ncu)"
```

## 2. 写入 sudoers 规则

```bash
sudo visudo -f /etc/sudoers.d/kernel-profiler-ncu
```

写入一行，替换用户名和路径：

```text
USERNAME ALL=(root) NOPASSWD: /usr/local/cuda-12.4/bin/ncu
```

`USERNAME` 是 `whoami` 输出的登录用户名；路径使用 agent 提示中的 `ncu` 绝对路径。

不要写 `NOPASSWD: ALL`。

## 3. 验证

```bash
sudo -n /usr/local/cuda-12.4/bin/ncu --version
sudo -n ncu --version
sudo -n /usr/local/cuda-12.4/bin/ncu --list-sections
```

如果不再提示密码，配置成功。

## 4. 后续 profile 固定同一个默认 ncu

正常情况下，后续脚本继续直接执行当前环境的 `ncu`，不需要在每条 profile 命令中写绝对路径：

```bash
scripts/ncu_collect_kernel_profile.sh \
  --sudo \
  --target-cmd "./gemm" \
  --kernel-name my_kernel \
  --kernel-regex ".*my_kernel.*" \
  --stages auto
```

如果服务器的 sudo `secure_path` 导致 `sudo -n ncu --version` 不能解析 `ncu`，才临时显式指定同一路径：

```bash
scripts/ncu_collect_kernel_profile.sh \
  --ncu-bin /usr/local/cuda-12.4/bin/ncu \
  --sudo \
  --target-cmd "./gemm" \
  --kernel-name my_kernel \
  --kernel-regex ".*my_kernel.*" \
  --stages auto
```

如果 `profile-target.yaml` 中记录配置，默认保持：

```yaml
profiling:
  ncu_bin: "ncu"

privilege:
  mode: "full_sudo"
```

只有在你明确需要绕过 sudo `secure_path` 或固定非默认 CUDA 环境时，才把 `profiling.ncu_bin` 改成同一个绝对路径。
