#!/usr/bin/env bash
# Tess-4.5-27B 一键运维入口：服务启停 / 状态 / 模型下载，交互菜单 + CLI 子命令
# 用法: ./onekey_start.sh [start|stop|status|restart|health|logs|download|help]
#       无参数进入交互菜单
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

# ── 配置：configs/local.sh（gitignored）→ 环境变量覆盖；tracked 文件零字面路径 ──
# 契约：同名环境变量优先级高于 local.sh — source 前保存外部导出值，source 后恢复
_env_keys="LLAMA_SERVER_BIN TESS_MODEL_DIR TESS_PORT HF_ENDPOINT TESS_START_WAIT TESS_STOP_WAIT TESS_LOG_MAX_BYTES TESS_LOG_KEEP TESS_DL_MIN_GB TESS_MAIN_GGUF TESS_DRAFT_GGUF TESS_MMPROJ TESS_CTX TESS_API_KEY TESS_VRAM_HEADROOM_MB"
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
# 模型变体选型：TESS_MAIN_GGUF 显式设置优先；TESS_DRAFT_GGUF set-but-empty = 无 draft（start 不加 --spec-type）
MAIN_GGUF="${TESS_MAIN_GGUF:-Tess-4.5-27B-Q4_K_M.gguf}"
DRAFT_GGUF="mtp-Tess-4.5-27B-Q4_K_M.gguf"
if [ "${TESS_DRAFT_GGUF+x}" = "x" ]; then
    DRAFT_GGUF="$TESS_DRAFT_GGUF"
fi
MODEL="${MODEL_DIR:+${MODEL_DIR}/${MAIN_GGUF}}"
MTP_DRAFT=""
if [ -n "$DRAFT_GGUF" ] && [ -n "$MODEL_DIR" ]; then
    MTP_DRAFT="${MODEL_DIR}/${DRAFT_GGUF}"
fi
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

# GPU 状态展示（download 预检信息项；不影响下载本身）
gpu_status_report() {
    command -v nvidia-smi >/dev/null 2>&1 || { warn "未找到 nvidia-smi — 无 NVIDIA GPU 或驱动未安装"; return 0; }
    local line
    while IFS= read -r line; do
        msg "GPU: ${line}"
    done < <(nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu --format=csv,noheader 2>/dev/null)
}

# download 预检：磁盘可用空间硬门禁 + GPU 状态展示
dl_preflight() { # $1=dir $2=need_gb（可选，缺省 TESS_DL_MIN_GB；最终不小于 TESS_DL_MIN_GB 下限）
    local dir="$1"
    local need_gb="${2:-${TESS_DL_MIN_GB:-20}}"
    local floor="${TESS_DL_MIN_GB:-20}"
    local avail
    if [ "$need_gb" -lt "$floor" ]; then
        need_gb="$floor"
    fi
    msg "── 下载预检 ──"
    avail="$(df -BG --output=avail "$dir" 2>/dev/null | tail -n 1 | tr -dc '0-9' || true)"
    if [ -n "$avail" ]; then
        if [ "$avail" -lt "$need_gb" ]; then
            fail "磁盘可用 ${avail}GB < 预估需求 ${need_gb}GB — 清理磁盘或换目标目录"
            return 1
        fi
        msg "磁盘可用 ${avail}GB ≥ 预估需求 ${need_gb}GB ✅"
    else
        warn "无法探测磁盘可用空间（df 失败）— 继续下载"
    fi
    gpu_status_report
}

check_models() {
    local dir="${1:-$MODEL_DIR}"
    if [ -z "$dir" ]; then
        warn "未配置 TESS_MODEL_DIR — 复制 configs/paths.example.sh → configs/local.sh"
        return 1
    fi
    local missing=0 f
    for f in "${dir}/${MAIN_GGUF}"; do
        if [ -f "$f" ]; then
            ok "模型文件就绪: $f"
        else
            warn "缺少模型文件: $f"
            missing=1
        fi
    done
    if [ -n "$DRAFT_GGUF" ]; then
        for f in "${dir}/${DRAFT_GGUF}"; do
            if [ -f "$f" ]; then
                ok "draft 模型就绪: $f"
            else
                warn "缺少 draft 模型: $f"
                missing=1
            fi
        done
    fi
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
    # 显存余量预检：按当前选型判定（附加件/未知跳过；restart 场景 stop 已释放显存）
    local vram_need tag_cur
    tag_cur="$(catalog_tag_of_main "$MAIN_GGUF" || echo q4km)"
    if catalog_get "$tag_cur" && [ "$CAT_VRAM" != "0" ]; then
        vram_need="$CAT_VRAM"
    else
        vram_need=22
    fi
    if ! vram_preflight "$vram_need"; then
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
    nohup bash "$ROOT/scripts/server/start_server.sh" >"$LOG_FILE" 2>&1 &
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
    if [ -n "${TESS_API_KEY:-}" ]; then
        echo "  鉴权     : 已启用（TESS_API_KEY · OpenAI Bearer）"
    else
        echo "  鉴权     : 未启用 — 设 TESS_API_KEY 开启（公网暴露前必做）"
    fi
    if [ -n "${TESS_MMPROJ:-}" ]; then
        echo "  视觉     : 启用（TESS_MMPROJ=${TESS_MMPROJ}）"
    else
        echo "  视觉     : 未启用（下载 mmproj 后设 TESS_MMPROJ=1 开启）"
    fi
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

# ── 模型目录（实测 HF 仓库变体 · 大小取自 HF tree API 2026-11-13）──
# 字段: tag|主模型|draft(空=无)|下载量GB|显存需求GB(0=附加件)|说明
MODEL_CATALOG=(
    "q4km|Tess-4.5-27B-Q4_K_M.gguf|mtp-Tess-4.5-27B-Q4_K_M.gguf|18.6|22|默认 · mtp 加速 · 已实测"
    "q6k|Tess-4.5-27B-Q6_K.gguf||22.1|27|质量更高 · 无 mtp draft · 需 CPU offload"
    "q8_0|Tess-4.5-27B-Q8_0.gguf|mtp-Tess-4.5-27B-Q8_0.gguf|31.8|36|精度最高 · 超 24GB 显存"
    "mmproj|mmproj-Tess-4.5-27B-F16.gguf||0.9|0|可选附加 · 视觉投影 · 服务端未接线"
)

gpu_total_vram_mib() {
    nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -n 1 | tr -dc '0-9'
}

# GPU used 采样：等待读数稳定（两次一致）或 ~10s 上限 — restart 后 CUDA 释放有延迟
gpu_used_mib_stable() {
    local prev cur i
    prev="$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null | head -n 1 | tr -dc '0-9')"
    for i in 1 2 3 4 5; do
        sleep 2
        cur="$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null | head -n 1 | tr -dc '0-9')"
        if [ -n "$cur" ] && [ "$cur" = "$prev" ]; then
            echo "$cur"
            return 0
        fi
        prev="$cur"
    done
    echo "${cur:-$prev}"
}

# 本服务（managed pid 且确为 llama-server）当前 GPU 占用 — restart/stop 场景视为可回收
our_pid_reclaimable() {
    local pid
    pid="$(pid_from_file || true)"
    [ -z "$pid" ] && return 0
    if ! pid_is_llama "$pid"; then
        return 0
    fi
    nvidia-smi --query-compute-apps=pid,used_memory --format=csv,noheader,nounits 2>/dev/null \
        | awk -F', *' -v p="$pid" '$1==p {gsub(/[^0-9]/,"",$2); print $2; exit}'
}

# start 前显存余量预检：$1=vram_need_gb
# free = 总显存 - 当前占用 + 本服务可回收部分；need = 选型需求 + TESS_VRAM_HEADROOM_MB（默认 1024）
# 注：视觉（mmproj ~1.2GB）已包含在 22GB 选型估算与实测余量的差值内，无需另加
vram_preflight() {
    local total used reclaimable free_mib need_mib
    local headroom_mb="${TESS_VRAM_HEADROOM_MB:-1024}"
    total="$(gpu_total_vram_mib)"
    if [ -z "$total" ]; then
        return 0
    fi
    used="$(gpu_used_mib_stable)"
    if [ -z "$used" ]; then
        return 0
    fi
    reclaimable="$(our_pid_reclaimable)"
    reclaimable="${reclaimable:-0}"
    free_mib=$(( total - used + reclaimable ))
    need_mib=$(( $1 * 1024 + headroom_mb ))
    if [ "$free_mib" -lt "$need_mib" ]; then
        fail "GPU 可用约 ${free_mib}MiB < 需求 ${need_mib}MiB（${1}GB 选型 + ${headroom_mb}MiB 余量）— 先停占用者，或 TESS_CTX=16384 降上下文"
        return 1
    fi
    msg "GPU 可用约 ${free_mib}MiB ≥ 需求 ${need_mib}MiB ✅（含本服务可回收 ${reclaimable}MiB）"
    if [ -n "${TESS_MMPROJ:-}" ] && [ "${TESS_CTX:-32768}" -ge 32768 ] 2>/dev/null; then
        warn "视觉 + 32K ctx 实测占用 ~23.4GB/24.5GB（余 ~1.1GB）— 大图/并发场景建议 TESS_CTX=16384"
    fi
}

# 显存判定：need ≤ 总显存 → 推荐；≤ 总+4GB → 紧张；否则不推荐
vram_verdict() { # $1=vram_need_gb $2=total_mib
    local need_gb="$1" total_mib="$2"
    if [ -z "$total_mib" ]; then
        echo "未知"
    elif [ $((need_gb * 1024)) -le "$total_mib" ]; then
        echo "推荐"
    elif [ $((need_gb * 1024)) -le $((total_mib + 4096)) ]; then
        echo "紧张"
    else
        echo "不推荐"
    fi
}

catalog_get() { # $1=tag → 填充 CAT_MAIN/CAT_DRAFT/CAT_SIZE/CAT_VRAM/CAT_NOTE；未登记 return 1
    local row tag main draft size vram note
    for row in "${MODEL_CATALOG[@]}"; do
        IFS='|' read -r tag main draft size vram note <<<"$row"
        if [ "$tag" = "$1" ]; then
            CAT_MAIN="$main"; CAT_DRAFT="$draft"; CAT_SIZE="$size"; CAT_VRAM="$vram"; CAT_NOTE="$note"
            return 0
        fi
    done
    return 1
}

catalog_tag_of_main() { # 反查：主模型文件名 → tag（未登记返回空）
    local row tag main rest
    for row in "${MODEL_CATALOG[@]}"; do
        IFS='|' read -r tag main rest <<<"$row"
        if [ "$main" = "$1" ]; then
            echo "$tag"
            return 0
        fi
    done
}

# 交互选型菜单：输出选中 tag；取消/EOF return 1（默认选第一个「推荐」条目）
model_select_menu() {
    local total_mib verdict tag main draft size vram note idx pick sel
    local default_tag="" default_set=""
    total_mib="$(gpu_total_vram_mib)"
    if [ -n "$total_mib" ]; then
        echo "本机 GPU 显存: $((total_mib / 1024))GB"
    fi
    echo "── 模型目录（依本机环境推荐）──"
    idx=0
    for row in "${MODEL_CATALOG[@]}"; do
        IFS='|' read -r tag main draft size vram note <<<"$row"
        idx=$((idx + 1))
        if [ "$vram" = "0" ]; then
            verdict="可选附加"
        else
            verdict="$(vram_verdict "$vram" "$total_mib")"
            if [ "$verdict" = "推荐" ] && [ -z "$default_set" ]; then
                default_tag="$tag"; default_set=1
            fi
        fi
        [ -n "$default_set" ] || default_tag="$tag"
        printf " %d) %-7s [%s] 下载 %sGB · %s\n" "$idx" "$tag" "$verdict" "$size" "$note"
    done
    if read -r -p "选择序号或 tag [回车=${default_tag}]: " pick; then
        :
    else
        warn "输入流结束 — 取消选型"
        return 1
    fi
    pick="${pick:-$default_tag}"
    case "$pick" in
        b|back|q|quit) return 1 ;;
    esac
    if [ "$pick" -eq "$pick" ] 2>/dev/null; then
        sel="$(printf '%s\n' "${MODEL_CATALOG[@]}" | sed -n "${pick}p" | cut -d'|' -f1)"
    else
        sel="$pick"
    fi
    if catalog_get "$sel"; then
        echo "$sel"
        return 0
    fi
    warn "无效选择: ${sel}"
    return 1
}

# 选型写回 configs/local.sh 托管块（幂等；失败仅 warn 不打断下载）
write_model_selection() { # $1=主模型文件名 $2=draft 文件名（可空=无 draft）
    local cfg="${ROOT}/configs/local.sh"
    if [ ! -f "$cfg" ]; then
        warn "configs/local.sh 不存在 — 选型未写回，请手动添加: export TESS_MAIN_GGUF=\"$1\""
        return 0
    fi
    local bb="# >>> codemender model-select (auto) >>>"
    local be="# <<< codemender model-select <<<"
    local tmp="${cfg}.tmp.$$"
    if ! awk -v b="$bb" -v e="$be" 'index($0,b)==1{skip=1;next} index($0,e)==1{skip=0;next} !skip' "$cfg" > "$tmp" 2>/dev/null; then
        warn "选型写回失败（读写受限）— 保持原配置"
        rm -f "$tmp" 2>/dev/null || true
        return 0
    fi
    {
        echo "$bb"
        echo "export TESS_MAIN_GGUF=\"$1\""
        if [ -n "$2" ]; then
            echo "export TESS_DRAFT_GGUF=\"$2\""
        else
            echo "export TESS_DRAFT_GGUF=\"\"  # 无 mtp draft"
        fi
        echo "$be"
    } >> "$tmp" && mv "$tmp" "$cfg" || { warn "选型写回失败 — 保持原配置"; rm -f "$tmp" 2>/dev/null || true; return 0; }
    msg "选型已写回 configs/local.sh（托管块）— 下次 start 生效"
}

# ── 模型下载 ────────────────────────────────────────────────────────
# 用法: download [目录] [模型tag] — 缺省目录=TESS_MODEL_DIR，缺省 tag=当前配置选型
#       无参数且交互终端 → 走选型菜单
cmd_download_menu() {
    local tag
    if ! tag="$(model_select_menu)"; then
        return 0
    fi
    catalog_get "$tag" || return 0
    local dldir=""
    read -r -p "下载目录 [回车=${MODEL_DIR:-未配置}]: " dldir || dldir=""
    cmd_download "${dldir:-$MODEL_DIR}" "$tag" || true
}

cmd_download() { # $1=目录 $2=模型 tag（缺省=当前配置选型；未登记回退 q4km）
    local dl_dir="${1:-$MODEL_DIR}"
    if [ -z "$dl_dir" ]; then
        fail "未指定下载目录 — 用法: ./onekey_start.sh download <目录>，或先配置 configs/local.sh 的 TESS_MODEL_DIR"
        return 1
    fi
    local tag="${2:-}"
    if [ -z "$tag" ]; then
        tag="$(catalog_tag_of_main "$MAIN_GGUF" || echo q4km)"
    fi
    if ! catalog_get "$tag"; then
        fail "未知模型 tag: ${tag}（可选: q4km/q6k/q8_0/mmproj）"
        return 1
    fi
    command -v hf >/dev/null 2>&1 || { fail "未找到 hf CLI（pip install -U huggingface_hub）"; return 1; }
    mkdir -p "$dl_dir"
    # 幂等短路：按选型文件集判断，已就绪则不重复下载
    if [ -f "${dl_dir}/${CAT_MAIN}" ] && { [ -z "$CAT_DRAFT" ] || [ -f "${dl_dir}/${CAT_DRAFT}" ]; }; then
        ok "模型文件已就绪（${tag}: ${CAT_MAIN}）— 跳过下载（如需强制重下请先删除目标文件）"
        return 0
    fi
    # 预检需求量 = 选型下载量(取整) + 3GB 余量，且不低于 TESS_DL_MIN_GB 下限
    if ! dl_preflight "$dl_dir" "$(( ${CAT_SIZE%%.*} + 3 ))"; then
        return 1
    fi
    local ts
    ts="$(date +%Y%m%d_%H%M%S)"
    local dl_log="${LOG_DIR}/download-${ts}.log"
    msg "下载仓库: ${HF_REPO} → ${dl_dir}（选型: ${tag} · ${CAT_NOTE}）"
    msg "下载源: ${HF_ENDPOINT_VAL} · 日志: logs/download-${ts}.log（断点续传，可重复执行）"
    local -a dl_files=("$CAT_MAIN")
    if [ -n "$CAT_DRAFT" ]; then
        dl_files+=("$CAT_DRAFT")
    fi
    # 包裹失败路径：hf 失败/中断不得被 set -e 腰斩（pipefail），给出可续传指引
    # 规避 socks 代理坑：ALL_PROXY=socks:// 会被 httpx 判为非法 → 显式剔除
    if ! env -u ALL_PROXY -u all_proxy HF_ENDPOINT="$HF_ENDPOINT_VAL" \
        hf download "$HF_REPO" "${dl_files[@]}" \
        --local-dir "$dl_dir" 2>&1 | tee "$dl_log"; then
        fail "hf 下载失败/中断（断点续传，可重试）— 日志: logs/download-${ts}.log"
        return 1
    fi
    if [ -f "${dl_dir}/${CAT_MAIN}" ] && { [ -z "$CAT_DRAFT" ] || [ -f "${dl_dir}/${CAT_DRAFT}" ]; }; then
        ok "模型下载完成并校验通过: ${dl_dir}（${tag}）"
        if [ "$CAT_VRAM" != "0" ] && { [ "$CAT_MAIN" != "$MAIN_GGUF" ] || [ "$CAT_DRAFT" != "$DRAFT_GGUF" ]; }; then
            write_model_selection "$CAT_MAIN" "$CAT_DRAFT"
        fi
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
            7) cmd_download_menu || true ;;
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
  download [目录] [tag]  下载模型（hf CLI，断点续传；tag: q4km/q6k/q8_0/mmproj，
                        缺省=当前配置选型；无参数交互终端 → 环境感知选型菜单）

其他:
  help              本帮助

环境变量（可入 configs/local.sh）:
  TESS_PORT=8000    服务端口（start_server.sh 同步读取）
  TESS_LOG_MAX_BYTES=10485760   server.log 轮转阈值（字节）
  TESS_LOG_KEEP=3   轮转保留份数
  TESS_DL_MIN_GB=20 download 预检磁盘可用空间下限（GB）
  TESS_MAIN_GGUF    主模型文件名（选型菜单自动写回，默认 Q4_K_M）
  TESS_DRAFT_GGUF   mtp draft 文件名（设空 = 无 draft，start 不加 --spec-type）
  TESS_MMPROJ       视觉投影（=1 自动探测 mmproj-*.gguf；缺省关闭）
  TESS_CTX=32768    上下文长度（开视觉后显存紧张可降 16384）
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
        download)
            if [ -n "${2:-}" ]; then
                cmd_download "$2" "${3:-}"
            elif [ -t 0 ]; then
                cmd_download_menu
            else
                cmd_download
            fi
            ;;
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

# 可测性钩子：ONEKEY_NO_EXEC=1 时仅加载定义不执行（供 source 单测）
if [ "${ONEKEY_NO_EXEC:-0}" != "1" ]; then
    run_cmd "$@"
fi
