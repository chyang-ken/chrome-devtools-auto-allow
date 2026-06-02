#!/usr/bin/env bash
# 按需启停 cdp-auto-allow，替代作者默认的常驻 LaunchAgent。
#
# 设计动机：作者默认用 KeepAlive 的 LaunchAgent 让自动点「允许」常驻 7x24，
# 等于把 Chrome「每次远程调试都要人工确认」这道安全防线对所有 Chrome 永久拆掉。
# 改成按需启停后，风险窗口收缩到「实际在跑 agent 浏览器任务的那几分钟」，
# 由使用者真正控制开关，而不是后台一直开着。
#
# 用法:
#   on-demand.sh start    # 开始 agent 浏览器任务前拉起
#   on-demand.sh stop     # 任务结束后停掉
#   on-demand.sh status   # 查看当前状态
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCPT="$ROOT_DIR/scripts/cdp-auto-allow.scpt"
PIDFILE="/tmp/cdp-auto-allow.ondemand.pid"
OUT_LOG="/tmp/cdp-auto-allow.out.log"
ERR_LOG="/tmp/cdp-auto-allow.err.log"

is_running() {
  [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null
}

case "${1:-}" in
  start)
    if is_running; then
      echo "already running (PID $(cat "$PIDFILE"))"
      exit 0
    fi
    nohup /usr/bin/osascript "$SCPT" >"$OUT_LOG" 2>"$ERR_LOG" &
    echo $! > "$PIDFILE"
    echo "started PID $! — 自动点「允许」已开启，记得任务完成后 stop"
    ;;
  stop)
    if is_running; then
      kill "$(cat "$PIDFILE")" 2>/dev/null || true
    fi
    # 兜底：清理任何按脚本路径遗漏的实例（比如旧的常驻进程）
    pkill -f "cdp-auto-allow.scpt" 2>/dev/null || true
    rm -f "$PIDFILE"
    echo "stopped — 防线已恢复"
    ;;
  status)
    if is_running; then
      echo "running (PID $(cat "$PIDFILE"))"
    else
      echo "stopped"
    fi
    ;;
  *)
    echo "usage: $0 start|stop|status" >&2
    exit 1
    ;;
esac
