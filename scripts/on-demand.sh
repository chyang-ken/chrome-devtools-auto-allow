#!/usr/bin/env bash
# 按需运行 cdp-auto-allow，替代作者默认的常驻 LaunchAgent。
#
# 设计动机：作者默认用 KeepAlive 的 LaunchAgent 让自动点「允许」常驻 7x24，
# 等于把 Chrome「每次远程调试都要人工确认」这道安全防线对所有 Chrome 永久拆掉。
# 改成按需运行后，风险窗口收缩到「实际在跑 agent 浏览器任务的那几秒」。
#
# 推荐用法是 watch（点火即忘、自带窗口、到点自杀），由 agent hook 在浏览器类工具
# 调用前触发，跟具体浏览器工具完全解耦：
#   on-demand.sh watch [秒数]   # 看守 N 秒(默认 60)后自动退出；再次调用则续期，不会起第二个
#   on-demand.sh stop           # 立即停掉
#   on-demand.sh status         # 查看状态与剩余窗口
#   on-demand.sh start          # 永久运行(无窗口)，手动/调试用；stop 才停
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCPT="$ROOT_DIR/scripts/cdp-auto-allow.scpt"
PIDFILE="/tmp/cdp-auto-allow.ondemand.pid"
DEADLINE="/tmp/cdp-auto-allow.deadline"
OUT_LOG="/tmp/cdp-auto-allow.out.log"
ERR_LOG="/tmp/cdp-auto-allow.err.log"

is_running() {
  [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null
}

launch() {  # 后台拉起看守进程（若未在跑）
  if is_running; then return 0; fi
  nohup /usr/bin/osascript "$SCPT" >"$OUT_LOG" 2>"$ERR_LOG" &
  echo $! > "$PIDFILE"
}

case "${1:-}" in
  watch)
    secs="${2:-60}"
    echo $(( $(date +%s) + secs )) > "$DEADLINE"   # 写/刷新截止时间 = 续期
    launch
    echo "watching ${secs}s (PID $(cat "$PIDFILE")) — 窗口内出现授权框会被自动点掉，到点自退"
    ;;
  start)
    rm -f "$DEADLINE"          # 无截止 = 永久运行
    if is_running; then echo "already running (PID $(cat "$PIDFILE"))"; exit 0; fi
    launch
    echo "started PID $(cat "$PIDFILE") — 永久运行，记得手动 stop"
    ;;
  stop)
    if is_running; then kill "$(cat "$PIDFILE")" 2>/dev/null || true; fi
    pkill -f "cdp-auto-allow.scpt" 2>/dev/null || true   # 兜底清理任何遗漏实例
    rm -f "$PIDFILE" "$DEADLINE"
    echo "stopped — 防线已恢复"
    ;;
  status)
    if is_running; then
      if [[ -f "$DEADLINE" ]]; then
        left=$(( $(cat "$DEADLINE") - $(date +%s) ))
        echo "running (PID $(cat "$PIDFILE"))，watch 窗口剩 ${left}s"
      else
        echo "running (PID $(cat "$PIDFILE"))，永久模式"
      fi
    else
      echo "stopped"
    fi
    ;;
  *)
    echo "usage: $0 watch [秒数] | stop | status | start" >&2
    exit 1
    ;;
esac
