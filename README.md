# Codemender — Tess-4.5-27B 本机大模型 API

基于 **Tess-4.5-27B**（Qwen3.6-27B 微调，自带 MTP draft head）在 RTX 4090 上部署的
本机大模型服务：OpenAI 兼容端点 `http://localhost:8000/v1`（模型 `tess-4.5-27b`），
用于本机各项目的代码审查/优化与 DeepSeek Harness 集成。

## 快速开始

> 本机没有编译好的 `llama-server` 二进制？先看 [`docs/build-llamacpp.md`](build-llamacpp.md)（CUDA 从源码构建，pin b9478 支持 draft-mtp）。

```bash
# 0) 首次使用：配置本机路径（不入库）
cp configs/paths.example.sh configs/local.sh && $EDITOR configs/local.sh

# 1) 下载/校验模型（hf CLI，断点续传；已下载则秒级校验）
./onekey_start.sh download

# 2) 后台启动服务（等待 /health 就绪）
./onekey_start.sh start

# 3) 接入 Harness：按 env.example 填表（Provider: tess-local · :8000/v1）
```

无参运行 `./onekey_start.sh` 进入交互菜单（1-7 + h/q）。

## 服务管理（onekey_start.sh）

| 命令 | 说明 |
|------|------|
| `start` | 后台启动（nohup + `logs/llama-server.pid` + `logs/server.log`），启动前校验模型文件，缺失时提示先 `download` |
| `stop` | 优雅停止（TERM → 超时 KILL） |
| `restart` | 重启（幂等） |
| `status` | 状态（managed / 外部启动 / 僵尸 pidfile）+ `/health` 探活 + 模型文件校验 + 局域网/广域网地址（广域网需端口转发；**服务无鉴权，暴露需谨慎**） |
| `health` | 仅 `GET /health` |
| `logs` | 跟踪服务日志（`tail -f`） |
| `download [目录]` | 下载/校验模型；指定非默认目录时提示与 `TESS_MODEL_DIR` 差异 |

### 配置覆盖

真实路径统一放 `configs/local.sh`（复制 `configs/paths.example.sh` 填写，已 gitignore，
tracked 文件不含机器路径）；同名环境变量优先级更高。

| 项 | 环境变量 | 默认 |
|----|----------|------|
| 端口 | `TESS_PORT` | `8000` |
| 模型目录 | `TESS_MODEL_DIR` | `configs/local.sh` |
| llama-server 路径 | `LLAMA_SERVER_BIN` | `configs/local.sh` |
| 下载源 | `HF_ENDPOINT` | `https://hf-mirror.com` |
| 启动就绪等待（秒） | `TESS_START_WAIT` | `180` |
| 停止等待（秒） | `TESS_STOP_WAIT` | `60` |
| 日志轮转阈值（字节） | `TESS_LOG_MAX_BYTES` | `10485760`（10MB） |
| 日志轮转保留份数 | `TESS_LOG_KEEP` | `3` |

> `start` 内置端口预检：端口被其他进程占用时直接失败并提示换 `TESS_PORT`；
> `server.log` 超阈值自动轮转为 `server.log.1`（滚动保留 `TESS_LOG_KEEP` 份）。

> 网络坑：HF/httpx 下载遇 `ALL_PROXY=socks://` 非法值会失败，`download` 已自动 `env -u ALL_PROXY` 规避。

## 性能实测（RTX 4090 · Q4_K_M · 32K ctx）

详见 `bench/report.md` · 复跑 `bash bench/run_bench.sh`：

- 生成速度：短上下文 **74.29 tok/s**（vs 无投机基线 49 tok/s → **1.52×**，时间节省 34%）
- 长上下文（~9731 tok）：prefill **2466 tok/s** · 生成 93.45 tok/s
- draft-mtp 接受率：短 49.7% / 长 76.6%

## 手动调试与工具链

```bash
bash scripts/start_server.sh            # 前台启动（调试用；路径同样读 configs/local.sh）
bash scripts/review/batch_review.sh <项目目录>   # 批量代码审查（调用本机 API）
```

审查/优化 prompt 模板见 `templates/`。

## 目录结构

```
codemender/
├── onekey_start.sh    # 一键运维入口（菜单 + CLI）
├── env.example        # Harness「自定义模型 API」填表对照
├── configs/           # paths.example.sh（模板）· local.sh（本地私有 · 不入库）
├── scripts/           # start_server · batch_review · verify · verify_onekey
├── templates/         # 审查/优化 prompt
├── bench/             # 性能基准脚本与报告
└── CHANGELOG.md       # 对外变更记录
```

## 验收

```bash
bash scripts/verify.sh    # L1 全量：关键文件 + 工具链 + onekey + 隐私防回退门禁
```

版本历史见 `CHANGELOG.md`（执行面板 `.growing/plan.md` 与归档不入库）。

## License

[MIT](LICENSE) · 模型权重不在本仓库内，其许可见上游 `migtissera/Tess-4.5-27B-GGUF`。
