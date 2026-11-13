# CHANGELOG

## [Unreleased]

### Added
- `onekey_start.sh`（SPRINT-03）：一键运维入口 — `start/stop/restart/status/health/logs` 服务管理（nohup 后台 + pidfile + `logs/server.log`，status 区分运行/停止/僵尸 pidfile，stop 优雅 TERM→KILL），交互菜单 + CLI 子命令双模
- `scripts/verify_onekey.sh`：onekey L1 验收（语法 + dispatch 冒烟，不真启停服务）
- `download` 子命令（SPRINT-03）：`hf` CLI 下载主模型 + MTP draft（`migtissera/Tess-4.5-27B-GGUF`），默认 `hf-mirror.com` 可 `HF_ENDPOINT` 覆盖，`env -u ALL_PROXY` 规避 socks 坑，断点续传，日志 `logs/download-*.log`
- 交互菜单（SPRINT-03）：无参运行进入菜单（start/stop/restart/status/health/logs/download），菜单与 CLI 子命令同源 dispatch

### Changed
- `README.md` 新增「一键运维」使用节与环境变量覆盖表；`scripts/verify.sh` 聚合 `verify_onekey.sh`

## [v0.1.8] - 2026-11-13

### Added
- `scripts/verify_task007.sh`：工具链验收（模板 + `batch_review.sh --dry-run`）
- SPRINT-02 闭环：TASK-007 试运行审查本仓 `scripts/`（3 文件、0 失败；报告目录 `.growing/trial-batch-review-TASK007/`）

### Changed
- `scripts/verify.sh` 聚合 TASK-007 验收
- `README.md` 快速开始与目录说明

## [v0.1.7] - 2026-11-13

### Added
- `env.example`：DeepSeek Harness「自定义模型 API」填表对照（本机 `tess-local` / `:8000/v1`）
- `templates/code_review_prompt.md`、`templates/optimize_prompt.md`：本机审查/优化 prompt 模板
- `scripts/batch_review.sh`：对本机项目源码批量调用 Tess API 生成审查报告

## [v0.1.6] - 2026-11-13

### Added
- `bench/run_bench.sh`：性能基准脚本（生成速度 / 长上下文 prefill + KV 占用 / draft-mtp 接受率）
- `bench/report.md`：首轮基准报告 — 短上下文 **74.29 tok/s**（vs 无投机基线 49 tok/s，**1.52×**，时间节省 **34% ≥ 25% 达标**）、长上下文 prefill 2466 tok/s、KV 占用 ~30% ctx、draft-mtp 接受率 49.7%/76.6%

## [v0.1.5] - 2026-11-13

### Changed
- plan.md 迁移至规范落点 `.growing/plan.md`（`workflow.json` → `plan_file`；`.growing/` 加入 .gitignore 不入库）
- plan.md 重构为执行面板：SPRINT-01（部署）闭环收敛为基线摘要，未完成 TASK-007/008 保留为下一 Sprint 候选

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
