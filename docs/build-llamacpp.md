# llama.cpp 从源码构建指南（CUDA · draft-mtp）

> 适用场景：本机没有编译好的 `llama-server` 二进制（换机 / 重装 / 新 GPU 机器）。
> 已有可用二进制的无需本文 — 直接在 `configs/local.sh` 填 `LLAMA_SERVER_BIN` 即可。

## 前置条件

| 项 | 要求 | 本仓验证锚点 |
|----|------|--------------|
| git / cmake | cmake ≥ 3.16 | cmake 3.25 |
| gcc/g++ | ≥ 11 | gcc 11.4（Ubuntu 22.04） |
| CUDA toolkit（nvcc） | ≥ 11.8 | 11.8 |
| NVIDIA 驱动 | ≥ CUDA runtime 对应版本 | 580.178.04（兼容 11.8/12.x runtime） |
| GPU | compute capability ≥ 6.0 | RTX 4090（sm_89） |

检查：`nvcc --version` · `cmake --version` · `nvidia-smi`。无 nvcc → 装 `nvidia-cuda-toolkit` 或官方 runfile（驱动已新，装 toolkit 不需要重装驱动）。

## 关键约束：版本必须 pin `b9478`

本仓服务端启动参数含 `--spec-type draft-mtp`（MTP 投机解码）。**该 flag 仅较新 llama.cpp 支持**，
随机版本编译出来可能直接 `invalid argument`。与现行服务保持同版本：

```bash
git clone https://github.com/ggml-org/llama.cpp
cd llama.cpp
git checkout b9478
```

> 网络坑：`ALL_PROXY=socks://` 非法值会让 git/http 失败 — 与 `download` 同源，`env -u ALL_PROXY git clone ...` 规避。

## 构建步骤

```bash
cmake -B build -DCMAKE_BUILD_TYPE=Release -DGGML_CUDA=ON
cmake --build build --config Release -j"$(nproc)" --target llama-server
```

- 产物：`build/bin/llama-server`（只需 server 时用 `--target llama-server` 省时）
- CUDA 全量编译约 10–30 分钟（取决于 CPU/内存，建议 ≥16GB 空闲内存）
- 旧文档里的 `LLAMA_CUBLAS=ON` 已废弃，新版一律 `GGML_CUDA=ON`
- 若 CMake 报 CUDA 架构未识别 → 显式指定：`-DCMAKE_CUDA_ARCHITECTURES=89`（4090）

## 安装与接线

```bash
mkdir -p "$HOME/install/llama/bin"
cp build/bin/llama-server "$HOME/install/llama/bin/"
```

然后二选一：

```bash
# a) 写进本机配置（推荐）
cp configs/paths.example.sh configs/local.sh   # 已有则跳过
# 编辑 configs/local.sh: export LLAMA_SERVER_BIN="$HOME/install/llama/bin/llama-server"

# b) 临时环境变量
LLAMA_SERVER_BIN="$HOME/install/llama/bin/llama-server" ./onekey_start.sh start
```

## 验证

```bash
"$HOME/install/llama/bin/llama-server" --version   # 应显示 b9478 与 CUDA
./onekey_start.sh restart                          # 重启生效（需模型已 download）
./onekey_start.sh status                           # running(managed) + /health 正常
bash scripts/verify.sh                             # 全量验收
```

## 常见坑速查

| 症状 | 原因 / 处理 |
|------|-------------|
| `--spec-type draft-mtp` 报无效参数 | 版本不对 — 未 pin `b9478`，回退到「关键约束」步骤 |
| CMake 找不到 CUDA 语言 | nvcc 不在 PATH — `which nvcc`；装 toolkit 或 source `CUDA 路径/bin` 环境 |
| 编译期显存/内存不足 | 减并发：`-j4`；或 `--target llama-server` 只编 server |
| 启动报 CUDA driver 版本不足 | 驱动过旧 — `nvidia-smi` 看 driver ≥ toolkit 要求 |
| `git clone` 卡住/报错 | `ALL_PROXY=socks://` 坑 — `env -u ALL_PROXY` 前缀 |
