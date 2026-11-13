#!/usr/bin/env bash
# 批量审查：文本源码模式（TASK-007）+ 图片模式（SPRINT-07 视觉审查）
# 用法:
#   文本: bash scripts/review/batch_review.sh <项目目录> [-o 输出目录] [-e 扩展名列表] [--dry-run]
#   图片: bash scripts/review/batch_review.sh -i <图片目录|文件1,文件2> [-o 输出目录] [--dry-run]
# 依赖: python3；llama-server 需在 :8000 运行（scripts/server/start_server.sh）
set -euo pipefail

BASE="${BASE:-http://localhost:8000}"
MODEL="${MODEL:-tess-4.5-27b}"
API_KEY="${TESS_API_KEY:-}"
CHUNK=300                     # 文本模式：单块最大行数
IMG_MAX_TOKENS=1024           # 图片模式：thinking 模型需给足预算（80 会耗尽在 reasoning）
TPL_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TPL_TEXT="$TPL_ROOT/templates/code_review_prompt.md"
TPL_IMG="$TPL_ROOT/templates/image_review_prompt.md"
EXT_DEFAULT="c,h,cpp,hpp,cc,py,sh,bash,ts,tsx,js,go,rs,java,kt,swift,yaml,yml"
IMG_EXT="png,jpg,jpeg,webp"

usage() {
    cat <<'EOF'
用法:
  文本模式: batch_review.sh <项目目录> [-o 输出目录] [-e ext1,ext2] [--dry-run]
  图片模式: batch_review.sh -i <图片目录|文件1,文件2> [-o 输出目录] [--dry-run]
环境变量: BASE(默认 http://localhost:8000) · MODEL(tess-4.5-27b) · TESS_API_KEY(可选鉴权)
EOF
}

TARGET="" OUT="" EXT="$EXT_DEFAULT" DRY=0 IMG="" MODE=text
while [ $# -gt 0 ]; do
    case "$1" in
        -o) OUT="$2"; shift 2 ;;
        -e) EXT="$2"; shift 2 ;;
        -i) IMG="$2"; MODE=img; shift 2 ;;
        --dry-run) DRY=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) TARGET="$1"; shift ;;
    esac
done

# ── 清单构建 ──
if [ "$MODE" = img ]; then
    [ -n "$IMG" ] || { echo "❌ -i 需要图片目录或文件列表"; usage >&2; exit 1; }
    TPL="$TPL_IMG"
    [ -f "$TPL" ] || { echo "❌ 缺少模板: $TPL"; exit 1; }
    if [ -d "$IMG" ]; then
        IMGBASE="$(cd "$IMG" && pwd)"
        OUT="${OUT:-$IMGBASE/.batch-review/$(date +%Y%m%d_%H%M%S)}"
        LIST=$(find "$IMGBASE" -maxdepth 2 -type f -not -path "*/.batch-review/*" \
            -not -path "*/.git/*" | grep -Ei "\.(${IMG_EXT//,/|})$" || true)
    else
        OUT="${OUT:-$PWD/.batch-review/$(date +%Y%m%d_%H%M%S)}"
        LIST=$(echo "$IMG" | tr ',' '\n' | sed 's|^ *||;s| *$||')
    fi
    ITEMS=$(echo "$LIST" | while IFS= read -r f; do [ -f "$f" ] && echo "$f"; done)
    [ -n "$ITEMS" ] || { echo "未找到图片文件（支持: $IMG_EXT）"; exit 1; }
else
    [ -n "$TARGET" ] && [ -d "$TARGET" ] || { echo "用法: $0 <项目目录> 或 -i <图片目录|文件列表>"; usage >&2; exit 1; }
    TPL="$TPL_TEXT"
    [ -f "$TPL" ] || { echo "❌ 缺少模板: $TPL"; exit 1; }
    TARGET="$(cd "$TARGET" && pwd)"
    OUT="${OUT:-$TARGET/.batch-review/$(date +%Y%m%d_%H%M%S)}"
    if git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1; then
        LIST=$(git -C "$TARGET" ls-files --cached --others --exclude-standard)
    else
        LIST=$(find "$TARGET" -type f -not -path "*/.git/*" -not -path "*/node_modules/*")
    fi
    ITEMS=$(echo "$LIST" | grep -E "\.($(echo "$EXT" | tr ',' '|'))$" | grep -vE "\.batch-review/" || true)
    [ -n "$ITEMS" ] || { echo "未找到匹配扩展名 [$EXT] 的文件"; exit 0; }
fi
mkdir -p "$OUT"
SYS=$(cat "$TPL")

if [ "$DRY" = 1 ]; then
    echo "[dry-run] 模式=$MODE · 共 $(echo "$ITEMS" | wc -l) 项 → 输出: $OUT"
    echo "$ITEMS"
    exit 0
fi

echo "审查 $(echo "$ITEMS" | wc -l) 项（$MODE 模式）→ $OUT"
DONE=0 FAIL=0
while IFS= read -r item; do
    if [ "$MODE" = img ]; then
        name="$(basename "$item")"
        dest="$OUT/${name%.*}.md"
        if python3 - "$item" "$SYS" "$MODEL" "$BASE" "$dest" "$API_KEY" "$IMG_MAX_TOKENS" <<'PY'
import json, sys, base64, urllib.request, pathlib
path, system, model, base, dest, api_key, max_tokens = sys.argv[1:8]
mime = {"jpg": "image/jpeg", "jpeg": "image/jpeg", "png": "image/png", "webp": "image/webp"}.get(
    pathlib.Path(path).suffix.lower().lstrip("."), "image/png")
data = base64.b64encode(pathlib.Path(path).read_bytes()).decode()
messages = [{"role": "system", "content": system},
            {"role": "user", "content": [
                {"type": "image_url", "image_url": {"url": f"data:{mime};base64,{data}"}},
                {"type": "text", "text": "审查这张截图/设计稿，按系统提示的格式输出。"}]}]
headers = {"Content-Type": "application/json"}
if api_key:
    headers["Authorization"] = f"Bearer {api_key}"
body = json.dumps({"model": model, "temperature": 0.2, "stream": False,
                   "max_tokens": int(max_tokens), "messages": messages}).encode()
try:
    r = json.loads(urllib.request.urlopen(urllib.request.Request(
        f"{base}/v1/chat/completions", body, headers), timeout=300).read())
    text = r["choices"][0]["message"]["content"] or "⚠️ content 为空 — thinking 模型可能耗尽 max_tokens，建议调大"
except Exception as e:
    text = f"❌ 调用失败: {e}"
    pathlib.Path(dest).write_text(f"# 视觉审查报告 · {pathlib.Path(path).name}\n\n{text}\n")
    sys.exit(1)
pathlib.Path(dest).write_text(f"# 视觉审查报告 · {pathlib.Path(path).name}\n\n{text}\n")
PY
        then DONE=$((DONE+1)); mark="✓"; else FAIL=$((FAIL+1)); mark="✗"; fi
        echo "  $mark $name"
    else
        rel="${item#./}"
        dest="$OUT/${rel//\//_}.md"
        if python3 - "$TARGET/$rel" "$SYS" "$MODEL" "$BASE" "$dest" "$API_KEY" "$CHUNK" <<'PY'
import json, sys, urllib.request, pathlib
path, system, model, base, dest, api_key, chunk = sys.argv[1:8]
chunk = int(chunk)
lines = pathlib.Path(path).read_text(errors="replace").splitlines()
ok = True
parts = []
headers = {"Content-Type": "application/json"}
if api_key:
    headers["Authorization"] = f"Bearer {api_key}"
for i in range(0, len(lines), chunk):
    seg = "\n".join(lines[i:i + chunk])
    head = f"文件: {path}（第 {i+1}-{min(i+chunk, len(lines))} 行 / 共 {len(lines)} 行）\n```"
    body = json.dumps({"model": model, "temperature": 0.2, "stream": False, "messages": [
        {"role": "system", "content": system},
        {"role": "user", "content": f"{head}\n{seg}\n```"}]}).encode()
    try:
        r = json.loads(urllib.request.urlopen(urllib.request.Request(
            f"{base}/v1/chat/completions", body, headers), timeout=300).read())
        parts.append(f"## 分块 {i//chunk + 1}（{i+1}-{min(i+chunk, len(lines))} 行）\n\n" +
                     r["choices"][0]["message"]["content"])
    except Exception as e:
        parts.append(f"## 分块 {i//chunk + 1}\n\n❌ 调用失败: {e}"); ok = False
pathlib.Path(dest).write_text(f"# 审查报告 · {path}\n\n" + "\n\n---\n\n".join(parts) + "\n")
sys.exit(0 if ok else 1)
PY
        then DONE=$((DONE+1)); mark="✓"; else FAIL=$((FAIL+1)); mark="✗"; fi
        echo "  $mark $rel"
    fi
done <<< "$ITEMS"

python3 - "$OUT" "$ITEMS" "$DONE" "$FAIL" "$MODE" <<'PY'
import sys, pathlib
out, items, done, fail, mode = sys.argv[1], sys.argv[2].splitlines(), sys.argv[3], sys.argv[4], sys.argv[5]
idx = pathlib.Path(out, "index.md")
label = "视觉审查汇总" if mode == "img" else "批量审查汇总"
idx.write_text(f"# {label}\n\n"
               f"- 时间: {pathlib.Path(out).name}\n- 完成: {done} · 失败: {fail} · 共 {len(items)}\n\n"
               "| 文件 | 报告 |\n|------|------|\n" +
               "\n".join(f"| {f} | [{pathlib.Path(f).stem}.md]({pathlib.Path(f).stem}.md) |" for f in items) + "\n")
PY
echo "✅ 完成 $DONE · 失败 $FAIL · 汇总: $OUT/index.md"
