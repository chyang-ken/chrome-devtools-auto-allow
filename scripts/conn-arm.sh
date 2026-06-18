#!/usr/bin/env bash
# 连接感知 arm —— 由 agent-hook.sh 在「会跑程序」的命令前后台启动。
#
# 原理（盯真相源，不猜命令）：agent 连 Chrome 的写法无穷（语言/库/端口/形态都可变），
# 唯一躲不掉的物理事实是——连 Chrome 必然建立一条到调试端口的 TCP 连接。本探测器盯
# 调试端口「基线外新增的外部连接」（= 本条命令亲手发起的那条），有活连接就给 auto-allow
# 续命（on-demand watch → scpt 去点授权框），连接消失 / 探测窗到则停止续命、看守自然收口。
#
# 性质：窗口贴合「这条命令真连 Chrome 的那几秒」——不敞开整个 agent 活跃期、不靠猜命令；
# 命令若根本没连 Chrome，探测几秒无新连接即早退、一个框都不点。安全闸（scpt 三重校验只
# 点远程调试框、看守短窗+自杀）全不变。
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PROBE_LOG=/tmp/cdp-auto-allow.probe.log
HOOK_LOG=/tmp/cdp-auto-allow.hook.log
PF="$HOME/Library/Application Support/Google/Chrome/DevToolsActivePort"
PORT="$(head -1 "$PF" 2>/dev/null)"
[ -z "${PORT:-}" ] && exit 0   # Chrome 没开调试口 → 没可连的，直接退

printf '%s PROBE-START port=%s\n' "$(date '+%H:%M:%S')" "$PORT" >> "$PROBE_LOG" 2>/dev/null

# 外部客户端连入调试端口的 PID 集合：排除 Chrome 自身，且只取「连向 :PORT」的 client 端
# （client 行 NAME 形如 127.0.0.1:54202->127.0.0.1:PORT；Chrome server 行是 PORT->...，被排除）
ext_conns() {
  lsof -nP -iTCP:"$PORT" 2>/dev/null | awk -v pat="->127.0.0.1:$PORT" \
    '/ESTABLISHED/ && $1 !~ /^(Google|Chrome|com\.google)/ && index($9,pat)>0 {print $2}' | sort -u
}

baseline="$(ext_conns)"   # 命令开始前已有的外部连接（如常驻 web-access proxy）
PROBE_SECS=45             # 探测窗上限
IDLE_QUIT=10             # 始终没新连接达此秒数 → 早退（命令大概率不连 Chrome）
GRACE=8                  # 见过新连接、其后连接消失达此秒数 → 收口
seen=0; idle=0; gone=0
start=$(date +%s)
while :; do
  now=$(date +%s); [ $((now-start)) -ge "$PROBE_SECS" ] && break
  cur="$(ext_conns)"
  new="$(comm -13 <(printf '%s\n' "$baseline") <(printf '%s\n' "$cur") 2>/dev/null)"
  if [ -n "$new" ]; then
    if [ "$seen" = 0 ]; then
      printf '%s PROBE-HIT | new-conn pid=%s port=%s\n' "$(date '+%H:%M:%S')" \
        "$(printf '%s' "$new" | tr '\n' ',')" "$PORT" >> "$HOOK_LOG" 2>/dev/null
    fi
    seen=1; idle=0; gone=0
    "$HERE/on-demand.sh" watch 20 >/dev/null 2>&1 &   # 有活连接 → 续命看守（scpt 去点框）
  else
    if [ "$seen" = 1 ]; then
      [ "$gone" = 0 ] && gone=$now
      [ $((now-gone)) -ge "$GRACE" ] && break          # 连接消失够久 → 收口
    else
      idle=$((idle+1))
      [ "$idle" -ge "$IDLE_QUIT" ] && break            # 始终没新连接 → 早退
    fi
  fi
  sleep 1
done
exit 0
