#!/usr/bin/env bash
# 本机路径配置模板 — 复制为 configs/local.sh 并按本机填写
# configs/local.sh 已被 .gitignore 忽略，不会入库；同名环境变量优先级更高
#
# export LLAMA_SERVER_BIN="$HOME/install/llama/bin/llama-server"
# export TESS_MODEL_DIR="/path/to/models/tess-4.5-27b"
# export TESS_PORT=8000
# export TESS_LOG_MAX_BYTES=10485760   # server.log 轮转阈值（字节，默认 10MB）
# export TESS_LOG_KEEP=3               # 轮转保留份数（server.log.1 ~ .N）
# export TESS_DL_MIN_GB=20             # download 预检磁盘可用空间下限（GB）
# export TESS_MAIN_GGUF="Tess-4.5-27B-Q4_K_M.gguf"     # 主模型文件名（选型菜单自动写回）
# export TESS_DRAFT_GGUF="mtp-Tess-4.5-27B-Q4_K_M.gguf" # mtp draft；设空 = 无 draft（不加 --spec-type）
# export TESS_MMPROJ=1                 # 视觉投影（=1 自动探测 mmproj-*.gguf；缺省关闭）
# export TESS_CTX=65536                # 上下文长度（64K+KV q8_0 实测 22000MiB；模型原生上限 256K）
# export TESS_KV_CACHE_TYPE=q8_0       # KV cache 量化（q8_0 减半显存 · native 切回原精度）
# export TESS_API_KEY="sk-xxx"         # API 鉴权（公网暴露前必做；客户端 Bearer 同值）
# export TESS_VRAM_HEADROOM_MB=1024    # start 显存预检安全余量（MiB）
# export TESS_KV_CPU_LAYERS=16         # 大上下文模式：第16层起KV放CPU（128K可行·慢·自动关draft；默认0关闭）
echo "这是模板 — 请复制为 configs/local.sh 后填写，不应直接执行。" >&2
exit 1
