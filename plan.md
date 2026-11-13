# plan.md — Tess-4.5-27B 本机大模型 API 项目规划

> 创建时间：2026-11-13 22:13
> 目标：在 RTX 4090（24GB）上基于 **Tess-4.5-27B** 构建本机大模型 API（OpenAI 兼容），
> 用于本机所有项目的优化（项目级编程助手，可接入 DeepSeek Harness）。

## 一、任务总览（待用户审核确认）

| # | 任务 | 状态 | 说明 |
|---|------|------|------|
| 1 | 仓库初始化（git init + README + CHANGELOG + .gitignore + 首次提交/tag） | ✅ 本次执行 | 骨架搭建 |
| 2 | 环境探测（GPU/CUDA/驱动/llama.cpp 是否已装） | ⬜ 待确认后执行 | 决定部署路径 |
| 3 | 模型获取（Tess-4.5-27B Q4_K_M GGUF + MTP draft head 下载） | ⬜ | 预计占用 ~17GB 磁盘 + 17GB 显存 |
| 4 | 部署 llama-server（Q4_K_M，4090 实测 96 tok/s 需挂载 draft head） | ⬜ | 一键启动脚本 `scripts/start_server.sh` |
| 5 | OpenAI 兼容 API 封装/网关（可选 FastAPI 反代：鉴权、限流、日志） | ⬜ | 供 DeepSeek Harness 直连 |
| 6 | DeepSeek Harness 接入配置（settings.yaml / Custom Provider 模板） | ⬜ | `configs/harness.example.yaml` |
| 7 | 本机项目优化工具链（代码审查 prompt 模板、批量优化脚本） | ⬜ | 后续迭代 |
| 8 | 性能基准与验收（tok/s、长上下文 KV cache 占用、token 节省率 ~25% 验证） | ⬜ | `bench/` |

## 二、技术要点备忘

- **量化**：Q4_K_M ≈ 17.0GB 显存，24GB 4090 余量充足，可开长上下文。
- **加速**：MTP draft head（投机解码）49 → 96 tok/s，务必随主模型一起下载挂载。
- **API**：`llama-server` 原生 OpenAI 兼容端点（`http://localhost:8000/v1`）。
- **Harness 集成**：`llm-pi-ai` 段配置 `baseURL` / `api: openai-completions` / `models`。

## 三、待用户确认的问题

1. 仓库根目录是否就用当前工作区 `/path/to/project`？（是 → 已初始化）
2. 模型存放路径偏好？（建议 `~/models/tess-4.5-27b/`，不放入 git 仓库）
3. 是否需要 FastAPI 网关层，还是直接用 llama-server 裸端点接入 Harness？

## 四、变更记录

- 2026-11-13：创建 plan.md，完成仓库初始化。
