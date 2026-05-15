# Nsight Compute NOPASSWD 配置指南

当 `ncu` 报 `ERR_NVGPUCTRPERM`，或 sudo 模式执行 `sudo -n "$(cat ./profile/ncu_path)" ...` 时提示需要密码，说明当前环境不能非交互式访问性能计数器。本次 profile 必须立刻停止。

这个 skill 不读取、不保存、不管道传输 sudo 密码。sudo 模式只使用 `./profile/ncu_path` 中的一条 `ncu` 绝对路径；默认内容是：

```text
/usr/local/cuda/bin/ncu
```

## 1. 找到当前 CUDA 环境的 ncu 路径

在你准备 profile 的 CUDA 环境中运行：

```bash
command -v ncu
readlink -f "$(command -v ncu)"
```

通常第一行是当前 `PATH` 命中的 `ncu`，第二行是软链接解析后的真实路径。请选择你希望固定使用的那个路径，例如：

```text
/usr/local/cuda-12.9/bin/ncu
```

## 2. 写入 sudoers 规则

```bash
sudo visudo -f /etc/sudoers.d/kernel-profiler-ncu
```

写入一行，替换用户名和你选择的路径：

```text
USERNAME ALL=(root) NOPASSWD: /usr/local/cuda-12.9/bin/ncu
```

`USERNAME` 是 `whoami` 输出的登录用户名。不要写 `NOPASSWD: ALL`。

## 3. 更新 ./profile/ncu_path

把同一个路径写入 `./profile/ncu_path`：

```bash
mkdir -p ./profile
printf '%s\n' '/usr/local/cuda-12.9/bin/ncu' > ./profile/ncu_path
```

`./profile/ncu_path` 中只能有一条路径。

## 4. 验证

```bash
sudo -n "$(cat ./profile/ncu_path)" --version
sudo -n "$(cat ./profile/ncu_path)" --list-sections
```

如果不再提示密码，配置成功。配置完成后，在下一次对话中重新发起 profile；agent 才能继续 sudo 模式采集。
