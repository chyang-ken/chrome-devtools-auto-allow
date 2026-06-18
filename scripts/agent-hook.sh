#!/usr/bin/env bash
# Claude Code PreToolUse(Bash) hook —— auto-allow 触发层（连接感知版）。
#
# 核心（agent 思维）：agent 连 Chrome 的脚本/命令是动态生成的，语言/库/端口/写法无穷，
# 靠「猜命令文本关键词」或「读代码特征」都枚举不全（实测 playwright/puppeteer/go/curl/
# node-e 全漏）。唯一躲不掉的物理事实是——连 Chrome 必然建立一条到调试端口的 TCP 连接。
# 所以触发改成【盯连接，不猜命令】：
#   (1) 命令文本已直接含连接标记（cdp-proxy/3456/devtools/remote-debugging/DevToolsActivePort/
#       web-access）→ 立刻 arm（快路径，明确无疑）。
#   (2) 否则命令只要「会跑程序」（解释器 / runner / 网络工具 / 可执行）→ 后台起连接探测器
#       conn-arm.sh：它盯调试端口「基线外新增的外部连接」（= 这条命令亲手发起的），有活连接
#       就给 auto-allow 续命（scpt 去点框）、连接消失即收。窗口贴合「真连 Chrome 的那几秒」，
#       不敞开整个 agent 活跃期、不靠猜命令内容。
#   (3) 纯文本命令（ls/cd/git/echo…）绝不连 Chrome → 直接跳过，零开销。
#
# 安全（不变）：scpt 只点远程调试框（三重校验）、看守短窗口+到点自杀、非永久常驻。
# 永远快速 exit 0，绝不阻塞工具。

HERE="$(cd "$(dirname "$0")" && pwd)"
input="$(cat 2>/dev/null)"

# (1) 命令文本直接含连接标记 → 立刻 arm（快路径）
if printf '%s' "$input" | grep -qiE 'cdp-proxy|web-access|:?3456|/devtools/browser|remote-debugging|DevToolsActivePort'; then
  snip="$(printf '%s' "$input" | tr '\n\t' '  ' | cut -c1-160)"
  printf '%s ARM | %s\n' "$(date '+%H:%M:%S')" "$snip" >> /tmp/cdp-auto-allow.hook.log 2>/dev/null
  "$HERE/on-demand.sh" watch 60 >/dev/null 2>&1 &
  exit 0
fi

# (2) 命令「会跑程序」（可能在内部连 Chrome）→ 后台起连接感知探测器（盯连接，不猜代码）。
#     粗筛宁滥勿缺：解释器 / go run / npx-pnpm-yarn / 网络工具(curl/wget/wscat) / ./可执行。
#     误判无害——探测器几秒无新连接就早退、不点任何框。
if printf '%s' "$input" | grep -qiE '(^|[^[:alpha:]])(node|bun|deno|tsx|ts-node|python3?|ruby|php|osascript|wscat|curl|wget)([^[:alpha:]]|$)|(^|[^[:alpha:]])go[[:space:]]+run|(^|[^[:alpha:]])npx([^[:alpha:]]|$)|(pnpm|yarn)[[:space:]]|\./[^[:space:]]'; then
  "$HERE/conn-arm.sh" >/dev/null 2>&1 &
fi

# (3) 其余纯文本命令：跳过
exit 0
