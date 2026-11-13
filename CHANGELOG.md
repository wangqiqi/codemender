# CHANGELOG

## [Unreleased]

## [v0.1.9] - 2026-11-13

### Added
- `onekey_start.sh`（SPRINT-03）：一键运维入口 — `start/stop/restart/status/health/logs` 服务管理（nohup 后台 + pidfile + `logs/server.log`，status 区分运行/停止/僵尸 pidfile，stop 优雅 TERM→KILL），交互菜单 + CLI 子命令双模
- `LICENSE`（MIT）：公开发布准备；README 新增 License 节（注明模型权重许可见上游）
- `scripts/verify_onekey.sh`：onekey L1 验收（语法 + dispatch 冒烟，不真启停服务）
- `download` 子命令（SPRINT-03）：`hf` CLI 下载主模型 + MTP draft（`migtissera/Tess-4.5-27B-GGUF`），默认 `hf-mirror.com` 可 `HF_ENDPOINT` 覆盖，`env -u ALL_PROXY` 规避 socks 坑，断点续传，日志 `logs/download-*.log`
- 交互菜单（SPRINT-03）：无参运行进入菜单（start/stop/restart/status/health/logs/download），菜单与 CLI 子命令同源 dispatch

### Changed
- **项目更名 Codemender**（原 Bigmodel）：README 标题、onekey 菜单横幅与状态栏头、plan 面板标题品牌化，磁盘目录同步改名 `codemender/`；模型 alias `tess-4.5-27b` 不变
- `README.md` 新增「一键运维」使用节与环境变量覆盖表；`scripts/verify.sh` 聚合 `verify_onekey.sh`
- **隐私脱敏**：本机路径（用户名/绝对路径）迁入 `configs/local.sh`（gitignored），tracked 文件零字面路径；新增 `configs/paths.example.sh` 模板与 `verify.sh` 防回退门禁；`start_server.sh`/`onekey_start.sh` 缺配置时 fail-closed 指引
- `.cursor/.../denylist.txt`：移除「作者/维护者标识」段中的真实个人标识，公开版保留占位注释
- `download [目录]`（SPRINT-03 follow-up）：支持指定下载目标目录，缺省仍为 `TESS_MODEL_DIR`；菜单选择后可输入路径或回车用默认；下载到非默认目录时提示与 `TESS_MODEL_DIR` 差异
- `README.md` 重构：快速开始前置 onekey 主入口与配置初始化，补实测性能数据（bench/report.md），服务管理改命令表，新增验收节
- 脚本布局整改（母版 scripts-layout 门禁）：`batch_review.sh` 移入 `scripts/review/`（根脚本 ≤40 逻辑行）并修正模板路径解析；新增 `scripts/README.md` 脚本矩阵 SSOT；补根 `.cursorignore`（scaffold 模板落地）

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
- plan.md：记录用户确认结果（模型路径与环境探测结果，现统一在 `configs/local.sh` 管理 · 无鉴权裸端点方案）、环境探测结果（4090 驱动正常，llama.cpp 需安装）

## [v0.1.0] - 2026-11-13

### Added
- 初始化仓库：README.md、plan.md、.gitignore
- plan.md：Tess-4.5-27B 本机大模型 API 项目整体规划（待用户审核确认后续任务）
