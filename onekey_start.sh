#!/usr/bin/env bash
# Tess-4.5-27B 一键运维入口：服务启停 / 状态 / 模型下载，交互菜单 + CLI 子命令
# 用法: ./onekey_start.sh [start|stop|status|restart|health|logs|download|help]
#       无参数进入交互菜单
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

# ── 配置（可用环境变量覆盖）─────────────────────────────────────────
LLAMA_BIN="${LLAMA_SERVER_BIN:-/home/user/install/llama/bin/llama-server}"
MODEL_DIR="${TESS_MODEL_DIR:-/media/user/data/models/tess-4.5-27b}"
MODEL="${MODEL_DIR}/Tess-4.5-27B-Q4_K_M.gguf"
MTP_DRAFT="${MODEL_DIR}/mtp-Tess-4.5-27B-Q4_K_M.gguf"
PORT="${TESS_PORT:-8000}"
BASE_URL="http://localhost:${PORT}"
# 下载源：默认 hf-mirror.com，可 HF_ENDPOINT 覆盖
HF_ENDPOINT_VAL="${HF_ENDPOINT:-https://hf-mirror.com}"
HF_REPO="migtissera/Tess-4.5-27B-GGUF"

LOG_DIR="${ROOT}/logs"
PID_FILE="${LOG_DIR}/llama-server.pid"
LOG_FILE="${LOG_DIR}/server.log"
START_WAIT_SECS="${TESS_START_WAIT:-180}"   # 模型加载 16.5GB，给足时间
STOP_WAIT_SECS="${TESS_STOP_WAIT:-60}"      # 卸载大模型也需时间

mkdir -p "$LOG_DIR"

# ── 通用工具 ────────────────────────────────────────────────────────
msg()  { echo "ℹ️  $*"; }
ok()   { echo "✅ $*"; }
warn() { echo "⚠️  $*" >&2; }
fail() { echo "❌ $*" >&2; }

pid_from_file() {
    [ -f "$PID_FILE" ] || return 1
    local pid
    pid="$(tr -d '[:space:]' < "$PID_FILE")"
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    echo "$pid"
}

pid_alive() {
    local pid="$1"
    kill -0 "$pid" 2>/dev/null
}

# 找到本项目的 llama-server 进程（含非本脚本启动的实例）
find_server_pid() {
    pgrep -f "llama-server .*--model ${MODEL}" 2>/dev/null | head -n 1
}

health_ok() {
    curl -sf --max-time 3 "${BASE_URL}/health" >/dev/null 2>&1
}

check_models() {
    local missing=0 f
    for f in "$MODEL" "$MTP_DRAFT"; do
        if [ -f "$f" ]; then
            ok "模型文件就绪: $f"
        else
            warn "缺少模型文件: $f"
            missing=1
        fi
    done
    return "$missing"
}

# ── 服务管理 ────────────────────────────────────────────────────────
cmd_start() {
    if health_ok; then
        ok "服务已在运行: ${BASE_URL} (pid $(find_server_pid || echo '?'))"
        return 0
    fi
    if ! check_models; then
        fail "模型文件缺失 — 请先运行: ./onekey_start.sh download"
        return 1
    fi
    if pid_from_file >/dev/null 2>&1; then
        warn "发现残留 pidfile（进程已死），清理后重启"
        rm -f "$PID_FILE"
    fi
    msg "启动 llama-server (port ${PORT}, ctx 32768, 全层 GPU offload)..."
    # start_server.sh 内部 exec → bash 的 PID 即 llama-server 的 PID
    nohup bash "$ROOT/scripts/start_server.sh" >"$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"
    local pid
    pid="$(cat "$PID_FILE")"
    msg "等待服务就绪（最长 ${START_WAIT_SECS}s，日志: logs/server.log）..."
    local waited=0
    while [ "$waited" -lt "$START_WAIT_SECS" ]; do
        if health_ok; then
            ok "服务就绪: ${BASE_URL}/v1 · 模型 tess-4.5-27b · pid ${pid}"
            return 0
        fi
        if ! pid_alive "$pid"; then
            fail "进程退出，最近日志："
            tail -n 20 "$LOG_FILE" >&2 || true
            rm -f "$PID_FILE"
            return 1
        fi
        sleep 1
        waited=$((waited + 1))
    done
    fail "等待超时（${START_WAIT_SECS}s）— 进程仍在，可查看: tail -f logs/server.log"
    return 1
}

cmd_stop() {
    local pid=""
    pid="$(pid_from_file || true)"
    if [ -z "$pid" ]; then
        pid="$(find_server_pid || true)"
    fi
    if [ -z "$pid" ]; then
        ok "服务未在运行"
        rm -f "$PID_FILE"
        return 0
    fi
    msg "停止 llama-server (pid ${pid}) — 先 TERM 等待优雅卸载..."
    kill -TERM "$pid" 2>/dev/null || true
    local waited=0
    while pid_alive "$pid" && [ "$waited" -lt "$STOP_WAIT_SECS" ]; do
        sleep 1
        waited=$((waited + 1))
    done
    if pid_alive "$pid"; then
        warn "优雅停止超时（${STOP_WAIT_SECS}s），强制 KILL"
        kill -KILL "$pid" 2>/dev/null || true
        sleep 1
    fi
    rm -f "$PID_FILE"
    if pid_alive "$pid"; then
        fail "进程 ${pid} 仍存活，请手动检查: pgrep -af llama-server"
        return 1
    fi
    ok "服务已停止"
}

cmd_restart() {
    cmd_stop || true
    cmd_start
}

cmd_status() {
    local pid state="stopped" detail=""
    pid="$(pid_from_file || true)"
    if [ -n "$pid" ] && pid_alive "$pid"; then
        state="running"
        detail="pid ${pid} (managed)"
    elif [ -n "$pid" ]; then
        state="stale-pidfile"
        detail="pidfile 残留 (pid ${pid} 已死)"
    else
        pid="$(find_server_pid || true)"
        if [ -n "$pid" ]; then
            state="running"
            detail="pid ${pid} (外部启动，无 pidfile)"
        fi
    fi
    echo "═══ Tess-4.5-27B 服务状态 ═══"
    echo "  状态     : ${state}"
    echo "  端点     : ${BASE_URL}/v1 (model: tess-4.5-27b)"
    if [ -n "$detail" ]; then
        echo "  进程     : ${detail}"
    fi
    if health_ok; then
        ok "健康检查: /health 正常"
    elif [ "$state" = "running" ]; then
        warn "进程在但 /health 未就绪（可能仍在加载模型）"
    fi
    check_models || msg "修复方式: ./onekey_start.sh download"
    case "$state" in
        running)    return 0 ;;
        stopped)    return 3 ;;
        *)          return 4 ;;
    esac
}

cmd_health() {
    if health_ok; then
        ok "健康检查通过: ${BASE_URL}/health"
    else
        fail "健康检查失败: ${BASE_URL}/health"
        return 1
    fi
}

cmd_logs() {
    [ -f "$LOG_FILE" ] || { warn "尚无日志: ${LOG_FILE}"; return 0; }
    msg "跟踪日志 logs/server.log（Ctrl-C 退出跟踪，服务不受影响）"
    tail -n 50 -f "$LOG_FILE"
}

# ── 模型下载 ────────────────────────────────────────────────────────
cmd_download() {
    command -v hf >/dev/null 2>&1 || { fail "未找到 hf CLI（pip install -U huggingface_hub）"; return 1; }
    local ts
    ts="$(date +%Y%m%d_%H%M%S)"
    local dl_log="${LOG_DIR}/download-${ts}.log"
    msg "下载仓库: ${HF_REPO} → ${MODEL_DIR}"
    msg "下载源: ${HF_ENDPOINT_VAL} · 日志: logs/download-${ts}.log（断点续传，可重复执行）"
    # 规避 socks 代理坑：ALL_PROXY=socks:// 会被 httpx 判为非法 → 显式剔除
    env -u ALL_PROXY -u all_proxy HF_ENDPOINT="$HF_ENDPOINT_VAL" \
        hf download "$HF_REPO" \
        "$(basename "$MODEL")" "$(basename "$MTP_DRAFT")" \
        --local-dir "$MODEL_DIR" 2>&1 | tee "$dl_log"
    if check_models; then
        ok "模型下载完成并校验通过"
    else
        fail "下载后仍缺模型文件 — 查看日志: logs/download-${ts}.log"
        return 1
    fi
}

# ── dispatch（TASK-003 补交互菜单）─────────────────────────────────
usage() {
    cat <<'EOF'
用法: ./onekey_start.sh [命令]

服务管理:
  start             后台启动 llama-server（nohup + pidfile + logs/server.log）
  stop              优雅停止（TERM → 超时 KILL）
  restart           重启（幂等：未运行则直接启动）
  status            服务状态 + 健康检查 + 模型文件校验
  health            仅健康检查 GET /health
  logs              跟踪服务日志（tail -f）

模型:
  download          下载主模型 + MTP draft（hf CLI，断点续传）

其他:
  help              本帮助
EOF
}

run_cmd() {
    case "${1:-}" in
        start)   cmd_start ;;
        stop)    cmd_stop ;;
        restart) cmd_restart ;;
        status)  cmd_status ;;
        health)  cmd_health ;;
        logs)    cmd_logs ;;
        download) cmd_download ;;
        help|-h|--help) usage ;;
        *) 
            if [ "$#" -eq 0 ]; then
                usage
                msg "（交互菜单开发中 — TASK-003）"
            else
                fail "未知命令: $1"
                usage >&2
                return 2
            fi
            ;;
    esac
}

run_cmd "$@"
