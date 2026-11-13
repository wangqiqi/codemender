#!/usr/bin/env bash
# Tess-4.5-27B 一键运维入口：服务启停 / 状态 / 模型下载，交互菜单 + CLI 子命令
# 用法: ./onekey_start.sh [start|stop|status|restart|health|logs|download|help]
#       无参数进入交互菜单
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

# ── 配置：configs/local.sh（gitignored）→ 环境变量覆盖；tracked 文件零字面路径 ──
# 契约：同名环境变量优先级高于 local.sh — source 前保存外部导出值，source 后恢复
_env_keys="LLAMA_SERVER_BIN TESS_MODEL_DIR TESS_PORT HF_ENDPOINT TESS_START_WAIT TESS_STOP_WAIT TESS_LOG_MAX_BYTES TESS_LOG_KEEP"
_env_saved=""
for _k in ${_env_keys}; do
    if [ -n "${!_k+x}" ]; then
        _env_saved="${_env_saved:+${_env_saved}|}${_k}=${!_k}"
    fi
done
if [ -f "${ROOT}/configs/local.sh" ]; then
    # shellcheck source=configs/local.sh
    source "${ROOT}/configs/local.sh"
fi
if [ -n "${_env_saved}" ]; then
    while IFS= read -r _item; do
        [ -n "$_item" ] || continue
        _k="${_item%%=*}"
        _v="${_item#*=}"
        printf -v "$_k" '%s' "$_v"
    done < <(printf '%s\n' "$_env_saved" | tr '|' '\n')
fi
unset _env_keys _env_saved _k _item _v
LLAMA_BIN="${LLAMA_SERVER_BIN:-}"
MODEL_DIR="${TESS_MODEL_DIR:-}"
MAIN_GGUF="Tess-4.5-27B-Q4_K_M.gguf"
DRAFT_GGUF="mtp-Tess-4.5-27B-Q4_K_M.gguf"
MODEL="${MODEL_DIR:+${MODEL_DIR}/${MAIN_GGUF}}"
MTP_DRAFT="${MODEL_DIR:+${MODEL_DIR}/${DRAFT_GGUF}}"
PORT="${TESS_PORT:-8000}"
BASE_URL="http://localhost:${PORT}"
# 下载源：默认 hf-mirror.com，可 HF_ENDPOINT 覆盖
HF_ENDPOINT_VAL="${HF_ENDPOINT:-https://hf-mirror.com}"
HF_REPO="migtissera/Tess-4.5-27B-GGUF"

LOG_DIR="${ROOT}/logs"
PID_FILE="${LOG_DIR}/llama-server.pid"
LOG_FILE="${LOG_DIR}/server.log"
# 数值 env 容错：非数字 → 回退默认（防 test 报错刷屏与行为漂移）
int_or() {
    case "$2" in
        ''|*[!0-9]*) echo "$1" ;;
        *) echo "$2" ;;
    esac
}
START_WAIT_SECS="$(int_or 180 "${TESS_START_WAIT:-180}")"    # 模型加载 16.5GB，给足时间
STOP_WAIT_SECS="$(int_or 60 "${TESS_STOP_WAIT:-60}")"        # 卸载大模型也需时间
LOG_MAX_BYTES="$(int_or 10485760 "${TESS_LOG_MAX_BYTES:-10485760}")"  # 日志轮转阈值（默认 10MB）
LOG_KEEP="$(int_or 3 "${TESS_LOG_KEEP:-3}")"                 # 轮转保留份数（server.log.1 ~ .N）
LOCK_FILE="${LOG_DIR}/onekey.lock"

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

# 校验 pid 确为 llama-server（防 pidfile 残留 pid 被系统复用后误杀无关进程）
pid_is_llama() {
    [ -r "/proc/$1/cmdline" ] || return 1
    tr '\0' ' ' < "/proc/$1/cmdline" | grep -q "llama-server"
}

# 找到本项目的 llama-server 进程（含非本脚本启动的实例）
# fail-closed：MODEL 未配置时禁用回退（防匹配本机任意 llama-server 误杀其他项目实例）
find_server_pid() {
    [ -n "$MODEL" ] || return 1
    local p
    p="$(pgrep -f "llama-server .*--model ${MODEL}" 2>/dev/null | head -n 1 || true)"
    if [ -n "$p" ] && pid_is_llama "$p"; then
        echo "$p"
    fi
}

health_ok() {
    curl -sf --max-time 3 "${BASE_URL}/health" >/dev/null 2>&1
}

# 模型身份校验：/health 200 ≠ 本服务 — 防其他 llama-server（不同模型）占同端口被误认
service_alias_ok() {
    curl -sf --max-time 3 "${BASE_URL}/v1/models" 2>/dev/null | grep -q 'tess-4.5-27b'
}

# 局域网 IP（首个非回环地址）
lan_ip() {
    hostname -I 2>/dev/null | awk '{print $1}'
}

# 广域网 IP（公网出口探测；优先复用本仓 github 代理配置，无则直连）
wan_ip() {
    local proxy
    proxy="$(git config --get http.https://github.com.proxy 2>/dev/null || true)"
    if [ -n "$proxy" ]; then
        curl -sf --max-time 3 -x "$proxy" https://api.ipify.org 2>/dev/null || true
    else
        curl -sf --max-time 3 https://api.ipify.org 2>/dev/null || true
    fi
}

# 端口占用探测（bash 内建 /dev/tcp，无外部依赖）
port_busy() {
    (exec 3<>"/dev/tcp/127.0.0.1/${1}") 2>/dev/null
}

# 日志轮转：超过 LOG_MAX_BYTES → server.log.1，滚动保留 LOG_KEEP 份
rotate_log() {
    [ -f "$LOG_FILE" ] || return 0
    local size
    size="$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)"
    size=$((size + 0))
    if [ "$size" -lt "$LOG_MAX_BYTES" ]; then
        return 0
    fi
    local i=$((LOG_KEEP - 1))
    while [ "$i" -ge 1 ]; do
        if [ -f "${LOG_FILE}.$i" ]; then
            mv "${LOG_FILE}.$i" "${LOG_FILE}.$((i + 1))"
        fi
        i=$((i - 1))
    done
    mv "$LOG_FILE" "${LOG_FILE}.1"
    msg "日志已轮转（${size}B ≥ ${LOG_MAX_BYTES}B，保留 ${LOG_KEEP} 份）"
}

check_models() {
    local dir="${1:-$MODEL_DIR}"
    if [ -z "$dir" ]; then
        warn "未配置 TESS_MODEL_DIR — 复制 configs/paths.example.sh → configs/local.sh"
        return 1
    fi
    local missing=0 f
    for f in "${dir}/${MAIN_GGUF}" "${dir}/${DRAFT_GGUF}"; do
        if [ -f "$f" ]; then
            ok "模型文件就绪: $f"
        else
            warn "缺少模型文件: $f"
            missing=1
        fi
    done
    return "$missing"
}

require_config() {
    if [ -z "$LLAMA_BIN" ] || [ -z "$MODEL_DIR" ]; then
        fail "未配置本机路径 — 复制 configs/paths.example.sh → configs/local.sh 并填写，或导出 LLAMA_SERVER_BIN / TESS_MODEL_DIR"
        return 1
    fi
}

# ── 服务管理 ────────────────────────────────────────────────────────
cmd_start() {
    if health_ok; then
        if service_alias_ok; then
            ok "服务已在运行: ${BASE_URL} (pid $(find_server_pid || echo '?'))"
        else
            fail "端口 ${PORT} 上是别的模型服务（/health 200 但非 tess-4.5-27b）— 换端口: TESS_PORT=<port> ./onekey_start.sh start"
            return 1
        fi
        return 0
    fi
    if ! require_config; then
        return 1
    fi
    if ! check_models; then
        fail "模型文件缺失 — 请先运行: ./onekey_start.sh download"
        return 1
    fi
    # 端口预检：被其他进程占用 → fail 并提示换端口（本服务自身已由 health_ok 短路）
    if port_busy "$PORT"; then
        fail "端口 ${PORT} 已被其他进程占用 — 换端口: TESS_PORT=<port> ./onekey_start.sh start"
        return 1
    fi
    # 仅当进程确实已死才清 pidfile（模型加载中 /health 未就绪时不得误删活服务的 pidfile）
    local stale_pid
    if stale_pid="$(pid_from_file)" && ! pid_alive "$stale_pid"; then
        warn "发现残留 pidfile（进程已死），清理后重启"
        rm -f "$PID_FILE"
    fi
    # 启动锁：覆盖 端口检查→spawn 窗口，防并发双 start 竞态（flock 缺失时降级跳过）
    local locked=0
    if command -v flock >/dev/null 2>&1; then
        exec 9>>"$LOCK_FILE"
        if flock -n 9; then
            locked=1
        else
            fail "另一个 start/stop 正在进行 — 稍后重试"
            return 1
        fi
    fi
    rotate_log
    local rc=0
    if ! _spawn_and_wait; then
        rc=1
    fi
    if [ "$locked" = 1 ]; then
        exec 9>&-
    fi
    return "$rc"
}

_spawn_and_wait() {
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
    # pidfile pid 已死或被系统复用给非 llama-server → 视为残留，清理后走 pgrep 回退
    if [ -n "$pid" ] && ! pid_is_llama "$pid"; then
        if pid_alive "$pid"; then
            warn "pidfile pid ${pid} 已被其他进程复用（非 llama-server）— 忽略"
        fi
        pid=""
        rm -f "$PID_FILE"
    fi
    if [ -z "$pid" ] && [ -n "$MODEL" ]; then
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
    echo "═══ Codemender 服务状态 ═══"
    echo "  状态     : ${state}"
    echo "  端点     : ${BASE_URL}/v1 (model: tess-4.5-27b)"
    if [ "$state" = "running" ]; then
        local lan wan
        lan="$(lan_ip)"
        wan="$(wan_ip)"
        if [ -n "$lan" ]; then
            echo "  局域网   : http://${lan}:${PORT}/v1"
        fi
        if [ -n "$wan" ]; then
            echo "  广域网   : http://${wan}:${PORT}/v1"
            warn "广域网可达还需路由器端口转发/防火墙放行；服务当前无鉴权 — 谨慎暴露"
        else
            echo "  广域网   : 探测失败（可能未联网/无公网出口）"
        fi
    fi
    if [ -n "$detail" ]; then
        echo "  进程     : ${detail}"
    fi
    if health_ok; then
        if service_alias_ok; then
            ok "健康检查: /health 正常"
        else
            warn "端口 ${PORT} 有 /health 200 但非 tess-4.5-27b — 可能是其他模型服务占用了端口"
        fi
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
    msg "跟踪日志 logs/server.log（Ctrl-C 退出跟踪，服务与菜单不受影响）"
    trap ':' INT   # Ctrl-C 只杀 tail：bash 捕获后延后处理，继续执行
    tail -n 50 -f "$LOG_FILE"
    trap - INT
}

# ── 模型下载 ────────────────────────────────────────────────────────
# 用法: download [目标目录] — 缺省用 configs/local.sh 的 TESS_MODEL_DIR
cmd_download() {
    local dl_dir="${1:-$MODEL_DIR}"
    if [ -z "$dl_dir" ]; then
        fail "未指定下载目录 — 用法: ./onekey_start.sh download <目录>，或先配置 configs/local.sh 的 TESS_MODEL_DIR"
        return 1
    fi
    command -v hf >/dev/null 2>&1 || { fail "未找到 hf CLI（pip install -U huggingface_hub）"; return 1; }
    mkdir -p "$dl_dir"
    local ts
    ts="$(date +%Y%m%d_%H%M%S)"
    local dl_log="${LOG_DIR}/download-${ts}.log"
    msg "下载仓库: ${HF_REPO} → ${dl_dir}"
    msg "下载源: ${HF_ENDPOINT_VAL} · 日志: logs/download-${ts}.log（断点续传，可重复执行）"
    # 包裹失败路径：hf 失败/中断不得被 set -e 腰斩（pipefail），给出可续传指引
    # 规避 socks 代理坑：ALL_PROXY=socks:// 会被 httpx 判为非法 → 显式剔除
    if ! env -u ALL_PROXY -u all_proxy HF_ENDPOINT="$HF_ENDPOINT_VAL" \
        hf download "$HF_REPO" "$MAIN_GGUF" "$DRAFT_GGUF" \
        --local-dir "$dl_dir" 2>&1 | tee "$dl_log"; then
        fail "hf 下载失败/中断（断点续传，可重试）— 日志: logs/download-${ts}.log"
        return 1
    fi
    if check_models "$dl_dir"; then
        ok "模型下载完成并校验通过: ${dl_dir}"
        if [ "$dl_dir" != "$MODEL_DIR" ]; then
            msg "提示: 服务默认从 TESS_MODEL_DIR 加载模型（${MODEL_DIR:-未配置}）— 要服务此目录请更新 configs/local.sh"
        fi
    else
        fail "下载后仍缺模型文件 — 查看日志: logs/download-${ts}.log"
        return 1
    fi
}

# ── 交互菜单 ────────────────────────────────────────────────────────
cmd_menu() {
    while true; do
        echo ""
        echo "======== Codemender 一键运维 ========"
        echo " 1) start      启动服务（后台 + 就绪等待）"
        echo " 2) stop       停止服务（优雅 TERM → KILL）"
        echo " 3) restart    重启服务"
        echo " 4) status     服务状态 + 健康检查 + 模型校验"
        echo " 5) health     仅健康检查"
        echo " 6) logs       跟踪服务日志（tail -f）"
        echo " 7) download   下载/校验模型（断点续传）"
        echo " h) help       命令行帮助"
        echo " q) quit       退出"
        echo "======================================="
        read -r -p "请选择: " choice || { echo ""; echo "再见。（EOF 退出）"; break; }
        case "${choice,,}" in
            1) cmd_start   || true ;;
            2) cmd_stop    || true ;;
            3) cmd_restart || true ;;
            4) cmd_status  || true ;;
            5) cmd_health  || true ;;
            6) cmd_logs    || true ;;
            7)
                read -r -p "下载目录 [回车=${MODEL_DIR:-未配置}]: " dldir || dldir=""
                cmd_download "$dldir" || true
                ;;
            h|help) usage ;;
            q|quit|exit) echo "再见。"; break ;;
            *) echo "无效选项: ${choice}" ;;
        esac
    done
}

# ── dispatch ────────────────────────────────────────────────────────
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
  download [目录]   下载主模型 + MTP draft（hf CLI，断点续传；缺省目录见 configs/local.sh）

其他:
  help              本帮助

环境变量（可入 configs/local.sh）:
  TESS_PORT=8000    服务端口（start_server.sh 同步读取）
  TESS_LOG_MAX_BYTES=10485760   server.log 轮转阈值（字节）
  TESS_LOG_KEEP=3   轮转保留份数
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
        download) cmd_download "${2:-}" ;;
        menu)    cmd_menu ;;
        help|-h|--help) usage ;;
        *)
            if [ "$#" -eq 0 ]; then
                cmd_menu
            else
                fail "未知命令: $1"
                usage >&2
                return 2
            fi
            ;;
    esac
}

run_cmd "$@"
