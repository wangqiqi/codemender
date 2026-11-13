#!/usr/bin/env bash
# 发版前轻量验收：关键文件存在 + bench 脚本可执行
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
for f in scripts/start_server.sh scripts/review/batch_review.sh bench/run_bench.sh env.example onekey_start.sh docs/build-llamacpp.md; do
  [ -f "$ROOT/$f" ] || { echo "FAIL missing $f"; exit 1; }
done
test -x "$ROOT/bench/run_bench.sh"
test -x "$ROOT/scripts/review/batch_review.sh"
bash "$ROOT/scripts/verify_task007.sh"
bash "$ROOT/scripts/verify_onekey.sh"
# 隐私门禁（防回退）：tracked 文件禁止本机用户名绝对路径（模式拼接避免自匹配）
privacy_pat='/home/jw''zhou|/media/jw''zhou'
if git -C "$ROOT" grep -nE "$privacy_pat" -- ':!.cursor' >/dev/null 2>&1; then
    echo "FAIL tracked files contain machine paths — 移入 configs/local.sh"
    git -C "$ROOT" grep -nE "$privacy_pat" -- ':!.cursor'
    exit 1
fi
echo "OK verify (core files present)"
