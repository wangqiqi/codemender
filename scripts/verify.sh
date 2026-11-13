#!/usr/bin/env bash
# 发版前轻量验收：关键文件存在 + bench 脚本可执行
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
for f in scripts/start_server.sh scripts/batch_review.sh bench/run_bench.sh env.example; do
  [ -f "$ROOT/$f" ] || { echo "FAIL missing $f"; exit 1; }
done
test -x "$ROOT/bench/run_bench.sh"
test -x "$ROOT/scripts/batch_review.sh"
echo "OK verify (core files present)"
