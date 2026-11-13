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
├── CHANGELOG.md
├── env.example        # Harness 自定义模型 API 填表对照
├── configs/           # Harness 模板配置
├── scripts/           # start_server · batch_review · verify
├── templates/         # 审查/优化 prompt
└── bench/             # 性能基准
```

## 快速开始

```bash
bash scripts/start_server.sh          # :8000 OpenAI 兼容 API
curl -s http://localhost:8000/health
bash scripts/batch_review.sh <项目目录>   # 批量代码审查
bash bench/run_bench.sh               # 性能基准
```

Harness 填表见根目录 `env.example`。
