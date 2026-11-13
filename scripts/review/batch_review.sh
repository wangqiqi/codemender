#!/usr/bin/env bash
# TASK-007 批量代码审查：对目标项目源码逐文件调用 Tess-4.5-27B 本机 API 生成审查报告
# 用法: bash scripts/review/batch_review.sh <项目目录> [-o 输出目录] [-e 扩展名(逗号分隔)] [--dry-run]
# 依赖: curl + python3；llama-server 需在 :8000 运行（scripts/server/start_server.sh）
set -euo pipefail

BASE="${BASE:-http://localhost:8000}"
MODEL="${MODEL:-tess-4.5-27b}"
CHUNK=300                     # 单块最大行数，超长文件分块审查
TEMPLATE="$(cd "$(dirname "$0")/../.." && pwd)/templates/code_review_prompt.md"
EXT_DEFAULT="c,h,cpp,hpp,cc,py,sh,bash,ts,tsx,js,go,rs,java,kt,swift,yaml,yml"

TARGET="" OUT="" EXT="$EXT_DEFAULT" DRY=0
while [ $# -gt 0 ]; do
    case "$1" in
        -o) OUT="$2"; shift 2 ;;
        -e) EXT="$2"; shift 2 ;;
        --dry-run) DRY=1; shift ;;
        *) TARGET="$1"; shift ;;
    esac
done
[ -n "$TARGET" ] && [ -d "$TARGET" ] || { echo "用法: $0 <项目目录> [-o 输出目录] [-e ext1,ext2] [--dry-run]"; exit 1; }
[ -f "$TEMPLATE" ] || { echo "❌ 缺少模板: $TEMPLATE"; exit 1; }
TARGET="$(cd "$TARGET" && pwd)"
TS=$(date +%Y%m%d_%H%M%S)
OUT="${OUT:-$TARGET/.batch-review/$TS}"
mkdir -p "$OUT"

# 文件清单：git 仓用 ls-files（尊重 .gitignore），否则 find
if git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1; then
    LIST=$(git -C "$TARGET" ls-files --cached --others --exclude-standard)
else
    LIST=$(find "$TARGET" -type f -not -path "*/.git/*" -not -path "*/node_modules/*")
fi
FILES=$(echo "$LIST" | grep -E "\.($(echo "$EXT" | tr ',' '|'))$" | grep -vE "\.batch-review/" || true)
[ -n "$FILES" ] || { echo "未找到匹配扩展名 [$EXT] 的文件"; exit 0; }

if [ "$DRY" = 1 ]; then echo "[dry-run] 将审查以下文件 → 输出: $OUT"; echo "$FILES"; exit 0; fi

SYS=$(cat "$TEMPLATE")
echo "审查 $(echo "$FILES" | wc -l) 个文件 → $OUT"
DONE=0 FAIL=0
while IFS= read -r f; do
    rel="${f#./}"
    dest="$OUT/${rel//\//_}.md"
    if python3 - "$TARGET/$rel" "$SYS" "$MODEL" "$BASE" "$dest" "$CHUNK" <<'PY'
import json, sys, urllib.request, pathlib
path, system, model, base, dest, chunk = sys.argv[1:7]
chunk = int(chunk)
lines = pathlib.Path(path).read_text(errors="replace").splitlines()
ok = True
parts = []
for i in range(0, len(lines), chunk):
    seg = "\n".join(lines[i:i + chunk])
    head = f"文件: {path}（第 {i+1}-{min(i+chunk, len(lines))} 行 / 共 {len(lines)} 行）\n```"
    body = json.dumps({"model": model, "temperature": 0.2, "stream": False, "messages": [
        {"role": "system", "content": system},
        {"role": "user", "content": f"{head}\n{seg}\n```"}]}).encode()
    try:
        r = json.loads(urllib.request.urlopen(urllib.request.Request(
            f"{base}/v1/chat/completions", body, {"Content-Type": "application/json"}), timeout=300).read())
        parts.append(f"## 分块 {i//chunk + 1}（{i+1}-{min(i+chunk, len(lines))} 行）\n\n" +
                     r["choices"][0]["message"]["content"])
    except Exception as e:
        parts.append(f"## 分块 {i//chunk + 1}\n\n❌ 调用失败: {e}"); ok = False
pathlib.Path(dest).write_text(f"# 审查报告 · {path}\n\n" + "\n\n---\n\n".join(parts) + "\n")
sys.exit(0 if ok else 1)
PY
    then DONE=$((DONE+1)); mark="✓"; else FAIL=$((FAIL+1)); mark="✗"; fi
    echo "  $mark $rel"
done <<< "$FILES"

python3 - "$OUT" "$FILES" "$DONE" "$FAIL" <<'PY'
import sys, pathlib
out, files, done, fail = sys.argv[1], sys.argv[2].splitlines(), sys.argv[3], sys.argv[4]
idx = pathlib.Path(out, "index.md")
idx.write_text("# 批量审查汇总\n\n"
               f"- 时间: {pathlib.Path(out).name}\n- 完成: {done} · 失败: {fail} · 共 {len(files)}\n\n"
               "| 文件 | 报告 |\n|------|------|\n" +
               "\n".join(f"| {f} | [{f.replace('/', '_')}.md]({f.replace('/', '_')}.md) |" for f in files) + "\n")
PY
echo "✅ 完成 $DONE · 失败 $FAIL · 汇总: $OUT/index.md"
