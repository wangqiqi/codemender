#!/usr/bin/env bash
# TASK-008 性能基准：生成速度 tok/s · 长上下文 prefill 与 KV 占用 · 投机解码节省率
# 用法: bash bench/run_bench.sh   （需 llama-server 已在 :8000 运行）
set -euo pipefail

BASE="${BASE:-http://localhost:8000}"
MODEL="${MODEL:-tess-4.5-27b}"
CTX=32768                      # 与 scripts/server/start_server.sh 一致
BASELINE_TOKS=49               # 无投机解码实测基线（见 CHANGELOG v0.1.4）
DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="$DIR/report.md"

# 单次请求，输出 JSON
req() { # $1=prompt $2=max_tokens $3=temp $4=cache_prompt(0/1)
    curl -s -m 300 "$BASE/v1/completions" -H "Content-Type: application/json" \
        -d "$(python3 - "$1" "$2" "$3" "$4" <<'PY'
import json, sys
print(json.dumps({"model": "tess-4.5-27b", "prompt": sys.argv[1],
                  "max_tokens": int(sys.argv[2]), "temperature": float(sys.argv[3]),
                  "cache_prompt": sys.argv[4] == "1", "stream": False}))
PY
)"
}

# 解析 timings → "tps prefill_tps accept%"
parse() {
    python3 - "$1" <<'PY'
import json, sys
t = json.loads(sys.argv[1])["timings"]
acc = t["draft_n_accepted"] / t["draft_n"] * 100 if t.get("draft_n") else 0
print(f"{t['predicted_per_second']:.2f} {t['prompt_per_second']:.2f} {acc:.1f} {t['prompt_n']}")
PY
}

echo "== [1/3] 短上下文生成速度（3 轮 × 256 tok）=="
for i in 1 2 3; do
    r=$(req "Write a detailed technical introduction to CUDA programming for GPU beginners." 256 0 1)
    echo "round$i: $(parse "$r")"
done | tee "$DIR/.bench_short.txt"

echo "== [2/3] 长上下文（~8K tok prefill + 256 tok 生成，不命中缓存）=="
LONG_PROMPT=$(python3 - <<'PY'
import itertools
sents = [
    "The GPU kernel processes a block of threads that cooperatively computes a tile of the output matrix.",
    "Shared memory staging reduces global memory traffic when neighbouring threads reuse overlapping data.",
    "Warp-level primitives such as shuffle and vote enable fast reductions without extra shared memory.",
    "Occupancy depends on register pressure, shared memory usage and the chosen block dimensions.",
    "Memory coalescing matters because consecutive threads should access consecutive addresses in a warp.",
    "Kernel fusion removes intermediate global round-trips at the cost of higher register pressure.",
]
print("Below is a long technical document. Read it and then write a new detailed paragraph "
      "about GPU memory coalescing strategies.\n\n" +
      "\n".join(itertools.cycle(sents) and (sents[i % len(sents)] for i in range(560))))
PY
)
r=$(req "$LONG_PROMPT" 256 0.8 0)
echo "long: $(parse "$r")" | tee "$DIR/.bench_long.txt"

echo "== [3/3] 汇总报告 → $OUT =="
python3 - "$DIR/.bench_short.txt" "$DIR/.bench_long.txt" "$OUT" "$CTX" "$BASELINE_TOKS" <<'PY'
import sys, statistics
short = [l.split()[1:] for l in open(sys.argv[1]) if l.startswith("round")]
tps = [float(r[0]) for r in short]
prefill = [float(r[1]) for r in short]
acc = [float(r[2]) for r in short]
long_ = [l.split()[1:] for l in open(sys.argv[2]) if l.startswith("long")][0]
l_tps, l_prefill, l_acc, l_prompt_n = float(long_[0]), float(long_[1]), float(long_[2]), int(long_[3])
ctx, baseline = int(sys.argv[4]), float(sys.argv[5])
tps_med = statistics.median(tps)
saved = (1 - baseline / tps_med) * 100
kv_pct = l_prompt_n / ctx * 100
kv_gb = 16.5 / 24 * 0  # 占位，实际按 KV 公式另列
rows = f"""# Tess-4.5-27B 性能基准报告

> 由 `bench/run_bench.sh` 生成 · 端点 `http://localhost:8000/v1` · ctx {ctx}

| 指标 | 数值 |
|------|------|
| 生成速度（短上下文中位数，3 轮） | **{tps_med:.2f} tok/s**（各轮: {', '.join(f'{v:.1f}' for v in tps)}） |
| prefill 速度（短上下文中位数） | {statistics.median(prefill):.2f} tok/s |
| 长上下文 prefill（~{l_prompt_n} tok） | {l_prefill:.2f} tok/s |
| 长上下文生成 | {l_tps:.2f} tok/s |
| KV cache 占用（长上下文时） | {l_prompt_n}/{ctx} tok ≈ **{kv_pct:.0f}%** ctx |
| draft-mtp 接受率（短/长） | {statistics.median(acc):.1f}% / {l_acc:.1f}% |
| 相对无投机基线（{baseline:.0f} tok/s）加速 | {tps_med / baseline:.2f}×（生成时间节省 **{saved:.0f}%**） |

> 「token 节省率 ~25%」验收口径：投机解码下单位生成时间相对基线节省 ≥25%，即 tok/s ≥ {baseline * 4 / 3:.0f}。
> 本轮 {saved:.0f}% → **{'✅ 达标' if saved >= 25 else '⚠️ 未达标'}**
"""
open(sys.argv[3], "w").write(rows)
print(rows)
PY
rm -f "$DIR/.bench_short.txt" "$DIR/.bench_long.txt"
