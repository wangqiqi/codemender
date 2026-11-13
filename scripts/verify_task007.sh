#!/usr/bin/env bash
# TASK-007：工具链存在性 + batch_review 干跑（不依赖 API）
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
for f in templates/code_review_prompt.md templates/optimize_prompt.md scripts/batch_review.sh; do
  [ -f "$ROOT/$f" ] || { echo "FAIL missing $f"; exit 1; }
done
bash "$ROOT/scripts/batch_review.sh" "$ROOT/scripts" --dry-run | grep -q start_server.sh
echo "OK TASK-007 verify (templates + batch_review dry-run)"
