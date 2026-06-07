#!/usr/bin/env bash
# Claude Code PreToolUse(Bash) hook —— auto-allow 的「触发层」。
#
# 设计：弹出「允许远程调试」框的本质，是 agent 把浏览器自动连到用户现有 profile。
# 这跟具体用哪个浏览器工具无关，所以触发也不该绑某个工具，而是绑「agent 要碰浏览器」
# 这个通用信号。本 hook 在每次 bash 调用前看一眼：若命令像是要连真实浏览器，就给
# auto-allow 点一个 60s 看守窗口（watch）；窗口内出现授权框会被自动点掉，到点自杀。
#
# 两个让它安全又轻的性质：
#   1. 误触发无害 —— auto-allow 只在真有授权框时才点，没框就空转后自退。故匹配宁滥勿缺。
#   2. 绝大多数 bash 调用一条 grep 即否决，零开销；永远快速 exit 0，绝不阻塞工具。
#
# 安装：在 ~/.claude/settings.json 的 PreToolUse → matcher "Bash" 的 hooks 里加一条
#       command 指向本脚本的绝对路径。

HERE="$(cd "$(dirname "$0")" && pwd)"
input="$(cat 2>/dev/null)"

# 原始 PreToolUse JSON 里出现"连真实浏览器"的标记才 arm。
# 标记取连接专属信号（cdp-proxy / 调试端口 3456 / 浏览器 WS 端点 / 远程调试开关 / web-access 入口），
# 不取宽泛词，避免把 `git clone …chrome-devtools…` 之类也算上。
if printf '%s' "$input" | grep -qiE 'cdp-proxy|web-access|:?3456|/devtools/browser|remote-debugging'; then
  "$HERE/on-demand.sh" watch 60 >/dev/null 2>&1 &
fi

exit 0
