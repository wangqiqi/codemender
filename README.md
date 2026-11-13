# Bigmodel — Tess-4.5-27B 本机大模型 API

基于 **Tess-4.5-27B**（Qwen3.6-27B 微调，自带 MTP draft head）在 RTX 4090 上部署的
本机大模型 API 服务，提供 OpenAI 兼容端点，用于本机所有项目的优化与 DeepSeek Harness 集成。

## 目标硬件
- GPU: RTX 4090 (24GB)
- 量化: Q4_K_M（~17.0GB VRAM）
- 预期性能: 96 tok/s（挂载 MTP draft head，投机解码）

## 目录规划
```
Bigmodel/
├── .growing/plan.md   # 执行面板（不入 git）
├── onekey_start.sh    # 一键运维入口（菜单 + CLI）
├── CHANGELOG.md
├── env.example        # Harness 自定义模型 API 填表对照
├── configs/           # Harness 模板配置
├── scripts/           # start_server · batch_review · verify · verify_onekey
├── templates/         # 审查/优化 prompt
└── bench/             # 性能基准
```

## 快速开始

```bash
bash scripts/start_server.sh          # :8000 OpenAI 兼容 API（前台，调试用）
curl -s http://localhost:8000/health
bash scripts/batch_review.sh <项目目录>   # 批量代码审查
bash bench/run_bench.sh               # 性能基准
```

Harness 填表见根目录 `env.example`。

## 一键运维（onekey_start.sh）

无参运行进入交互菜单；子命令亦可在脚本/CI 中直接调用：

```bash
./onekey_start.sh              # 交互菜单
./onekey_start.sh start        # 后台启动（nohup + logs/llama-server.pid + logs/server.log）
./onekey_start.sh status       # 状态 + 健康检查 + 模型文件校验
./onekey_start.sh stop         # 优雅停止（TERM → 超时 KILL）
./onekey_start.sh restart      # 重启（幂等）
./onekey_start.sh download     # 下载/校验模型（hf CLI，断点续传）
```

| 覆盖项 | 环境变量 | 配置来源 |
|--------|----------|----------|
| 端口 | `TESS_PORT` | 默认 `8000` |
| 模型目录 | `TESS_MODEL_DIR` | `configs/local.sh`（本地私有 · 不入库） |
| llama-server 路径 | `LLAMA_SERVER_BIN` | `configs/local.sh`（本地私有 · 不入库） |
| 下载源 | `HF_ENDPOINT` | 默认 `https://hf-mirror.com` |
| 启动就绪等待 | `TESS_START_WAIT` | 默认 `180`（秒） |

说明：真实本机路径统一放 `configs/local.sh`（复制 `configs/paths.example.sh` 填写，已被 `.gitignore` 忽略），tracked 文件不含机器路径；`download` 自动剔除非法 `ALL_PROXY=socks://`；`start` 前会先校验模型文件，缺失时提示先 `download`。
