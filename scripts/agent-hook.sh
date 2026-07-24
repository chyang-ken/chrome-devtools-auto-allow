#!/usr/bin/env bash
# Claude Code PreToolUse(Bash) hook —— auto-allow 触发层（连接感知版）。
#
# 核心：命令特征只作快路径；正确性来自受支持浏览器真实调试端口上的新连接。
#   (1) 明确的连接命令 → 立刻 arm。
#   (2) 其他可能运行程序的命令 → 先建立多浏览器/多端口基线，再放行命令并后台盯新连接。
#   (3) 明确不会连接浏览器的查看类命令（ls/cd/git/echo…）直接跳过。
#
# 安全（不变）：scpt 只点远程调试框（三重校验）、看守短窗口+到点自杀、非永久常驻。
# 永远快速 exit 0，绝不阻塞工具。

HERE="$(cd "$(dirname "$0")" && pwd)"
input="$(cat 2>/dev/null)"
decision="$(printf '%s' "$input" | node "$HERE/hook-decision.mjs" 2>/dev/null || printf 'probe')"

# (1) 命令文本直接含连接标记 → 立刻 arm（快路径）。
#     hook-decision 会先排除 echo/rg/git 等纯查看命令，避免仅仅提到关键词就开看守。
if [ "$decision" = "fast" ]; then
  snip="$(printf '%s' "$input" | tr '\n\t' '  ' | cut -c1-160)"
  printf '%s ARM | %s\n' "$(date '+%H:%M:%S')" "$snip" >> /tmp/cdp-auto-allow.hook.log 2>/dev/null
  "$HERE/on-demand.sh" watch 60 >/dev/null 2>&1 &
  exit 0
fi

# (2) 未知工具默认探测，避免把正确性绑在工具名枚举上。
#     用 ready 文件确保基线先于命令建立；等待有上限，不会被后台探测器卡住。
if [ "$decision" = "probe" ]; then
  ready="$(mktemp /tmp/cdp-auto-allow.ready.XXXXXX 2>/dev/null || true)"
  "$HERE/conn-arm.sh" --ready-file "$ready" >/dev/null 2>&1 &
  probe_pid=$!
  if [ -n "$ready" ]; then
    for _ in {1..25}; do
      [ -s "$ready" ] && break
      kill -0 "$probe_pid" 2>/dev/null || break
      sleep 0.02
    done
    rm -f "$ready"
  fi
fi

# (3) 其余纯查看命令：跳过。
exit 0
