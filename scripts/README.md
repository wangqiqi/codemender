# scripts/ — 脚本矩阵

| 脚本 | 层 | 用途 |
|------|-----|------|
| `start_server.sh` | 入口 | 前台启动 llama-server（调试用；路径读 `configs/local.sh`） |
| `verify.sh` | 入口 | L1 全量验收聚合（文件存在 + 工具链 + onekey + 隐私防回退） |
| `verify_onekey.sh` | 域 | onekey_start.sh L1（语法 + dispatch 冒烟，不真启停） |
| `verify_task007.sh` | 域 | 工具链验收（模板 + batch_review 干跑） |
| `review/batch_review.sh` | 工具 | 批量代码审查（调用本机 Tess API；`--dry-run` 支持） |

约定：根目录只放**入口脚本**（≤40 逻辑行）；实现型脚本放子目录（如 `review/`）；
新增脚本须在本表登记一行（SSOT）。
