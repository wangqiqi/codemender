# plan.md — Tess-4.5-27B 本机大模型 API 项目规划

> 创建时间：2026-11-13 22:13
> 目标：在 RTX 4090（24GB）上基于 **Tess-4.5-27B** 构建本机大模型 API（OpenAI 兼容），
> 用于本机所有项目的优化（项目级编程助手，可接入 DeepSeek Harness）。

## 一、任务总览（待用户审核确认）

| # | 任务 | 状态 | 说明 |
|---|------|------|------|
| 1 | 仓库初始化（git init + README + CHANGELOG + .gitignore + 首次提交/tag） | ✅ 本次执行 | 骨架搭建 |
| 2 | 环境探测（GPU/CUDA/驱动/llama.cpp 是否已装） | ✅ 2026-11-13 | 结果见第四节 |
| 3 | 模型获取（Tess-4.5-27B Q4_K_M GGUF + MTP draft head 下载） | 🔄 下载中 | 官方源 `migtissera/Tess-4.5-27B-GGUF`，共 ~18.6GB → `/media/user/data/models/tess-4.5-27b/` |
| 4 | 部署 llama-server（Q4_K_M，4090 实测 96 tok/s 需挂载 draft head） | 🔧 脚本已就绪 | 复用已有编译 b9478（CUDA 版，原生支持 `--spec-type draft-mtp`），`scripts/start_server.sh` 一键启动 |
| 5 | API 端点验证（无鉴权 OpenAI 兼容，直接供 Harness 调用） | 🔧 已简化 | 用户确认：本机自用不加鉴权/限流，跳过 FastAPI 网关 |
| 6 | DeepSeek Harness 接入配置（settings.yaml / Custom Provider 模板） | ⬜ | `configs/harness.example.yaml` |
| 7 | 本机项目优化工具链（代码审查 prompt 模板、批量优化脚本） | ⬜ | 后续迭代 |
| 8 | 性能基准与验收（tok/s、长上下文 KV cache 占用、token 节省率 ~25% 验证） | ⬜ | `bench/` |

## 二、技术要点备忘

- **量化**：Q4_K_M ≈ 17.0GB 显存，24GB 4090 余量充足，可开长上下文。
- **加速**：MTP draft head（投机解码）49 → 96 tok/s，务必随主模型一起下载挂载。
- **API**：`llama-server` 原生 OpenAI 兼容端点（`http://localhost:8000/v1`）。
- **Harness 集成**：`llm-pi-ai` 段配置 `baseURL` / `api: openai-completions` / `models`。

## 三、用户确认结果（2026-11-13）

1. ✅ 仓库根目录：`/path/to/project`（已初始化）
2. ✅ 模型存放路径：`/media/user/data/models/tess-4.5-27b/`（不入 git）
3. ✅ API 架构：**本机自用，不加鉴权/限流**，直接使用 `llama-server` 标准兼容端点供 DeepSeek Harness 调用（跳过 FastAPI 网关层，任务 5 简化为端点验证）

## 四、环境探测结果（2026-11-13）

| 项目 | 状态 | 详情 |
|------|------|------|
| GPU | ✅ | RTX 4090, 24564 MiB, 驱动 580.178.04, compute 8.9 |
| CUDA | ⚠️ | nvcc 为 11.8（编译 llama.cpp 可用；如遇新特性需求需升级 CUDA 12.x） |
| llama.cpp / ollama | ❌ 未安装 | 需自行编译（gcc 11.4 + cmake 3.25 满足要求）或下载预编译版 |
| Python | ✅ | 3.11.4 |
| 磁盘 | ✅ | /media/user/data 可用 1.1T（模型放这里） |
| 内存 | ✅ | 62GB，可用 48GB |

**结论**：硬件完全满足；需安装 llama.cpp（推荐从源码编译 CUDA 版本以获得最快 4090 性能 + draft head 支持）。

## 五、llama.cpp 复用结论（2026-11-13）

- 发现 `/home/user/install/llama/` 已有编译产物：**llama-server b9478**（2026-06-02，CUDA 11.8，`libggml-cuda` 正常链接）。
- 该版本已支持 `--spec-type draft-mtp` + `--model-draft`，**无需重新编译**。
- 官方 GGUF 仓库文件确认：`Tess-4.5-27B-Q4_K_M.gguf`（16.55GB）+ `mtp-Tess-4.5-27B-Q4_K_M.gguf`（2.03GB）+ 可选 mmproj（0.93GB，暂不下）。

## 六、变更记录

- 2026-11-13：创建 plan.md，完成仓库初始化。
