#!/usr/bin/env bash
# onekey_start.sh L1 验收：语法 + 子命令 dispatch 冒烟（不真启停服务）
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ONEKEY="$ROOT/onekey_start.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

[ -f "$ONEKEY" ] || fail "missing $ONEKEY"
[ -x "$ONEKEY" ] || fail "$ONEKEY not executable"

bash -n "$ONEKEY" || fail "syntax error"

# help 冒烟（两个入口都要能跑）
"$ONEKEY" help >/dev/null || fail "help failed"
"$ONEKEY" --help >/dev/null || fail "--help failed"

# status 冒烟（只读，不改状态；退出码 0/3/4 均合法：running/stopped/异常）
rc=0
"$ONEKEY" status >/dev/null || rc=$?
case "$rc" in
    0|3|4) ;;
    *) fail "status exit=$rc (期望 0/3/4)" ;;
esac

# dispatch 覆盖：服务管理子命令须有实现函数
for fn in cmd_start cmd_stop cmd_restart cmd_status cmd_health cmd_logs cmd_download; do
    grep -q "^${fn}()" "$ONEKEY" || fail "missing function ${fn}"
done

# 未知命令须非零退出
if "$ONEKEY" __no_such_cmd__ >/dev/null 2>&1; then
    fail "unknown command should exit non-zero"
fi

# 交互菜单冒烟：无参进菜单，喂 q 退出
echo q | "$ONEKEY" >/dev/null || fail "menu smoke failed"
grep -q "^cmd_menu()" "$ONEKEY" || fail "missing function cmd_menu"

# TESS_PORT 传导：start_server.sh 不得硬编码端口（防回退）
START_SH="$ROOT/scripts/server/start_server.sh"
bash -n "$START_SH" || fail "start_server.sh syntax error"
grep -q 'PORT="${TESS_PORT:-8000}"' "$START_SH" || fail "start_server.sh 未读 TESS_PORT（防回退）"

# 端口预检 + 日志轮转：函数与 env 缺一不可
grep -q "^port_busy()" "$ONEKEY" || fail "missing function port_busy"
grep -q "^rotate_log()" "$ONEKEY" || fail "missing function rotate_log"
grep -q 'TESS_LOG_MAX_BYTES' "$ONEKEY" || fail "missing TESS_LOG_MAX_BYTES"
grep -q 'TESS_LOG_KEEP' "$ONEKEY" || fail "missing TESS_LOG_KEEP"

# 环境变量优先契约：source local.sh 前后须有保存/恢复逻辑（防回退：local.sh 不得覆盖外部 env）
grep -q '_env_saved' "$ONEKEY" || fail "onekey 缺 env 优先恢复逻辑"
grep -q '_env_saved' "$START_SH" || fail "start_server.sh 缺 env 优先恢复逻辑"

# 边界加固：pid 校验 / 身份校验 / flock / 数值容错 / 跨平台轮转（防回退）
grep -q "^pid_is_llama()" "$ONEKEY" || fail "missing function pid_is_llama"
grep -q "^service_alias_ok()" "$ONEKEY" || fail "missing function service_alias_ok"
grep -q "^int_or()" "$ONEKEY" || fail "missing function int_or"
grep -q "^_spawn_and_wait()" "$ONEKEY" || fail "missing function _spawn_and_wait"
grep -q 'flock' "$ONEKEY" || fail "missing flock start lock"
grep -q 'wc -c' "$ONEKEY" || fail "rotate 应使用跨平台 wc -c（GNU stat 不可移植）"
grep -q "tr '\\\\0'" "$ONEKEY" || fail "pid_is_llama 应解析 /proc cmdline"
grep -q "trap ':' INT" "$ONEKEY" || fail "cmd_logs 缺 Ctrl-C 隔离"
grep -q "^lan_ip()" "$ONEKEY" || fail "missing function lan_ip"
grep -q "^wan_ip()" "$ONEKEY" || fail "missing function wan_ip"
grep -q "^dl_preflight()" "$ONEKEY" || fail "missing function dl_preflight"
grep -q "^gpu_status_report()" "$ONEKEY" || fail "missing function gpu_status_report"
grep -q 'TESS_DL_MIN_GB' "$ONEKEY" || fail "missing TESS_DL_MIN_GB"
grep -q '^MODEL_CATALOG=(' "$ONEKEY" || fail "missing MODEL_CATALOG"
grep -q '^vram_verdict()' "$ONEKEY" || fail "missing function vram_verdict"
grep -q '^write_model_selection()' "$ONEKEY" || fail "missing function write_model_selection"
grep -q '^model_select_menu()' "$ONEKEY" || fail "missing function model_select_menu"
grep -q 'TESS_MAIN_GGUF' "$START_SH" || fail "start_server.sh 未读 TESS_MAIN_GGUF"
grep -q 'TESS_DRAFT_GGUF+x' "$START_SH" || fail "start_server.sh 缺 set-but-empty draft 判定"
grep -q 'ARGS+=' "$START_SH" || fail "start_server.sh 缺条件 draft 参数"
grep -q 'TESS_MMPROJ' "$START_SH" || fail "start_server.sh 缺视觉投影接线"
grep -q 'TESS_CTX' "$START_SH" || fail "start_server.sh 缺 TESS_CTX"
grep -q 'TESS_MMPROJ_OFFLOAD' "$START_SH" || fail "start_server.sh 缺视觉驻留策略"
grep -q 'no-mmproj-offload' "$START_SH" || fail "start_server.sh 缺 CPU 驻留默认"
grep -q 'TESS_KV_CACHE_TYPE' "$START_SH" || fail "start_server.sh 缺 KV 量化配置"
grep -q 'cache-type-k' "$START_SH" || fail "start_server.sh 缺 --cache-type-k 接线"
grep -q 'TESS_UBATCH' "$START_SH" || fail "start_server.sh 缺 ubatch 配置"
grep -q 'ubatch-size' "$START_SH" || fail "start_server.sh 缺 --ubatch-size 接线"
grep -q 'TESS_MMPROJ' "$ONEKEY" || fail "onekey 缺 TESS_MMPROJ（status 视觉行/优先级表）"
grep -q 'TESS_API_KEY' "$START_SH" || fail "start_server.sh 缺 --api-key 接线"
grep -q 'TESS_API_KEY' "$ONEKEY" || fail "onekey 缺 TESS_API_KEY（status 鉴权行）"
grep -q '^vram_preflight()' "$ONEKEY" || fail "missing function vram_preflight"
grep -q '^our_pid_reclaimable()' "$ONEKEY" || fail "missing function our_pid_reclaimable"
grep -q 'TESS_VRAM_HEADROOM_MB' "$ONEKEY" || fail "missing TESS_VRAM_HEADROOM_MB"

echo "OK verify_onekey (L1)"
