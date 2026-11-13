# CHANGELOG

## [Unreleased]

### Added
- `download` 下载预检：磁盘可用空间硬门禁（`TESS_DL_MIN_GB`，默认 20GB，不足即 fail）+ GPU 状态展示（nvidia-smi）；模型已就绪时幂等跳过下载
- `docs/build-llamacpp.md`：llama.cpp 从源码构建指南（CUDA · pin b9478 保 draft-mtp · 安装接线 · 常见坑速查）；README 快速开始挂链接；verify.sh 登记该文档存在性
- onekey `start` 端口预检：端口被其他进程占用时直接失败并提示 `TESS_PORT` 换端口（bash `/dev/tcp` 探测，无外部依赖）
- `status` 展示局域网/广域网地址：`lan_ip`（`hostname -I`）+ `wan_ip`（ipify，自动复用本仓代理配置）— 广域网条目强制附带「无鉴权 · 需端口转发」安全警示
- 日志轮转：`TESS_LOG_MAX_BYTES`（默认 10MB）/ `TESS_LOG_KEEP`（默认 3）— `server.log` 超阈值自动轮转为 `server.log.1`

### Changed
- **开源公开化**：`git filter-repo` 重写全部历史 — 清除早期提交中的本机绝对路径（`/home/…`、`/media/…`），作者信息统一为 `wangqiqi <wangqiqi@users.noreply.github.com>`；`LICENSE` 版权人改为 GitHub handle；历史 tag v0.1.0~v0.1.9 随重写同步更新

### Fixed
- `TESS_PORT` 未传导：`start_server.sh` 曾硬编码 `PORT=8000`，`TESS_PORT` 只影响健康检查 URL（换端口必假失败）→ 现两脚本同读 `TESS_PORT`
- 环境变量优先契约失真：`configs/local.sh` 的 `export` 会在 `source` 时静默覆盖外部同名环境变量 → source 前保存、source 后恢复外部值（`onekey_start.sh` 与 `start_server.sh` 同源同修）
- `start` 误删活服务 pidfile：模型加载中（`/health` 未就绪）执行 start 曾清掉 pidfile → 现仅当进程确实已死才清残留
- **stop 误杀防护**：pidfile pid 被系统复用给非 llama-server → 识别并忽略（warn），不再盲杀；kill 前校验 `/proc/<pid>/cmdline`；`MODEL` 未配置时禁用 pgrep 回退（fail-closed，防匹配本机任意 llama-server）
- `download` 的 hf 失败/中断不再被 `set -e` 腰斩 — 现给出「断点续传可重试」指引并保留日志路径
- `start` 的 `/health` 短路增加模型身份校验（`/v1/models` alias）— 端口被其他模型实例占用时明确报错而非误报「已在运行」
- 边界加固：数值 env 非数字回退默认（`int_or`）；轮转改 `wc -c`（跨平台）；`flock` 启动锁防并发双实例；`logs` 的 Ctrl-C 只退跟踪不退脚本/菜单；菜单 EOF（Ctrl-D）优雅退出

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
