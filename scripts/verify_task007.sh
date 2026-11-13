#!/usr/bin/env bash
# TASK-007：工具链存在性 + batch_review 干跑（不依赖 API）
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
for f in templates/code_review_prompt.md templates/optimize_prompt.md templates/image_review_prompt.md scripts/review/batch_review.sh; do
  [ -f "$ROOT/$f" ] || { echo "FAIL missing $f"; exit 1; }
done
bash "$ROOT/scripts/review/batch_review.sh" "$ROOT/scripts" --dry-run | grep -q start_server.sh
# SPRINT-07：图片模式 dry-run（1x1 PNG 内联生成，不依赖 API/PIL）
SMOKE="$(mktemp /tmp/br-img-XXXX.png)"
printf 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==' | base64 -d > "$SMOKE"
bash "$ROOT/scripts/review/batch_review.sh" -i "$SMOKE" --dry-run | grep -q "模式=img"
rm -f "$SMOKE"
echo "OK TASK-007 verify (templates + batch_review dry-run · text+img)"
