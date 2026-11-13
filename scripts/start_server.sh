#!/usr/bin/env bash
# Tess-4.5-27B 本机 API 启动脚本（RTX 4090 优化）
# 端点: http://localhost:8000/v1 (OpenAI 兼容，无鉴权，供 DeepSeek Harness 调用)
set -euo pipefail

# 本机私有路径：configs/local.sh（gitignored）→ 环境变量覆盖；tracked 文件零字面路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/../configs/local.sh" ]; then
    # shellcheck source=../configs/local.sh
    source "${SCRIPT_DIR}/../configs/local.sh"
fi
LLAMA_BIN="${LLAMA_SERVER_BIN:-}"
MODEL_DIR="${TESS_MODEL_DIR:-}"
: "${LLAMA_BIN:?缺少 LLAMA_SERVER_BIN — 复制 configs/paths.example.sh → configs/local.sh 或导出环境变量}"
: "${MODEL_DIR:?缺少 TESS_MODEL_DIR — 复制 configs/paths.example.sh → configs/local.sh 或导出环境变量}"

MODEL="${MODEL_DIR}/Tess-4.5-27B-Q4_K_M.gguf"
MTP_DRAFT="${MODEL_DIR}/mtp-Tess-4.5-27B-Q4_K_M.gguf"
PORT=8000
CTX=32768          # 24GB 显存下 Q4_K_M(16.5GB) 预留 ~7GB 给 KV cache，32K 稳妥
GPU_LAYERS=999     # 全部层offload到GPU

for f in "$MODEL" "$MTP_DRAFT"; do
    [ -f "$f" ] || { echo "❌ 缺少模型文件: $f （先运行下载）"; exit 1; }
done

exec "$LLAMA_BIN" \
    --host 0.0.0.0 --port "$PORT" \
    --model "$MODEL" \
    --alias tess-4.5-27b \
    --ctx-size "$CTX" \
    --n-gpu-layers "$GPU_LAYERS" \
    --flash-attn on \
    --jinja \
    --spec-type draft-mtp \
    --model-draft "$MTP_DRAFT" \
    --threads "$(nproc)"
