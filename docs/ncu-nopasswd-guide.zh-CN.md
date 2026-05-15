# Nsight Compute NOPASSWD 配置指南

当 `ncu` 报 `ERR_NVGPUCTRPERM`，或 agent 使用 `sudo -n ncu ...` 时提示需要密码，说明当前环境不能非交互式访问性能计数器。这个 skill 不读取、不保存、不管道传输 sudo 密码；需要为选定 CUDA 环境里的精确 `ncu` 路径配置窄范围 `NOPASSWD`。

## 1. 确认当前 CUDA 环境的 ncu 路径

```bash
which ncu
readlink -f $(which ncu)
```

记下 `readlink -f` 输出的绝对路径，例如：

```text
/usr/local/cuda-12.4/bin/ncu
```

多 CUDA 环境服务器必须使用你准备 profile 的那个 CUDA 环境里的 `ncu`。

## 2. 写入 sudoers 规则

```bash
sudo visudo -f /etc/sudoers.d/kernel-profiler-ncu
```

写入一行，替换用户名和路径：

```text
USERNAME ALL=(root) NOPASSWD: /usr/local/cuda-12.4/bin/ncu
```

例如用户是 `zhoujie`：

```text
zhoujie ALL=(root) NOPASSWD: /usr/local/cuda-12.4/bin/ncu
```

不要写 `NOPASSWD: ALL`。

## 3. 验证

```bash
sudo -n /usr/local/cuda-12.4/bin/ncu --version
sudo -n /usr/local/cuda-12.4/bin/ncu --list-sections
```

如果不再提示密码，配置成功。

## 4. 后续 profile 固定同一个 ncu

后续运行脚本时显式指定相同路径：

```bash
scripts/ncu_collect_kernel_profile.sh \
  --ncu-bin /usr/local/cuda-12.4/bin/ncu \
  --sudo \
  --target-cmd "./gemm" \
  --kernel-name my_kernel \
  --kernel-regex ".*my_kernel.*" \
  --stages basic,speed-of-light
```

如果 `profile-target.yaml` 中记录配置，保持：

```yaml
profiling:
  ncu_bin: "/usr/local/cuda-12.4/bin/ncu"

privilege:
  mode: "full_sudo"
```
