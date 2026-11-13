# CHANGELOG

## [v0.1.4] - 2026-11-13

### Added
- 模型部署完成：Tess-4.5-27B Q4_K_M + MTP draft head（魔搭直连下载，校验通过）
- 服务上线：llama-server :8000，实测 80.27 tok/s（draft-mtp 接受率 57.4%），OpenAI 兼容端点验证通过

## [v0.1.3] - 2026-11-13

### Changed
- plan.md：下载源由 HF 改为魔搭 ModelScope 直连（~17MB/s），双文件并行下载中；记录 ALL_PROXY socks:// 环境坑

## [v0.1.2] - 2026-11-13

### Added
- scripts/start_server.sh：Tess-4.5-27B 一键启动脚本（b9478 + draft-mtp 投机解码）
- configs/harness.example.yaml：DeepSeek Harness 接入模板（openai-completions，无鉴权）

### Changed
- plan.md：确认复用已有 llama.cpp b9478（CUDA 版，支持 MTP）；模型开始后台下载（官方源 migtissera/Tess-4.5-27B-GGUF）

## [v0.1.1] - 2026-11-13

### Changed
- plan.md：记录用户确认结果（模型路径 `/media/user/data/models/`、无鉴权裸端点方案）、环境探测结果（4090 驱动正常，llama.cpp 需安装）

## [v0.1.0] - 2026-11-13

### Added
- 初始化仓库：README.md、plan.md、.gitignore
- plan.md：Tess-4.5-27B 本机大模型 API 项目整体规划（待用户审核确认后续任务）
