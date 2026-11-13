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
├── plan.md            # 任务规划（规则：>5 项任务先写入此文件审核）
├── CHANGELOG.md       # 变更日志（逆序，最新在上）
├── configs/           # 部署与 Harness 接入配置
├── scripts/           # 启动/下载/基准脚本
├── bench/             # 性能基准与验收
└── docs/              # 文档
```

## 快速开始（规划中）
详见 [plan.md](plan.md)。
