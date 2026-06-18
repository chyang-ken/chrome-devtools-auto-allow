#!/usr/bin/env bash
# Claude Code PreToolUse(Bash) hook —— auto-allow 的「触发层」。
#
# 设计：弹出「允许远程调试」框的本质，是 agent 把浏览器自动连到用户现有 profile。
# 这跟具体用哪个浏览器工具无关，也跟脚本叫什么名无关，只跟「这条命令会不会去连真实
# 浏览器」这个行为有关。命中就给 auto-allow 点一个 60s 看守窗口（watch）；窗口内出现
# 授权框会被自动点掉，到点自杀。
#
# 【agent 思维 / 2026-06-17 增强】直连 Chrome 的脚本常是 agent 动态生成的、名字随机、
# 一次性的，靠「认脚本名」永远追不上。所以这里【看脚本干什么，不看它叫什么】，两层识别：
#   (1) 命令文本直接含连接标记（cdp-proxy / 3456 / devtools / remote-debugging /
#       DevToolsActivePort / web-access），含内联代码 `node -e "...DevToolsActivePort..."`。
#   (2) 命令是跑一个脚本文件（node/bun/deno/tsx/python/osascript）时，读那个脚本的内容，
#       只要里面有直连 Chrome 的代码特征（读 DevToolsActivePort / 连 /devtools/browser /
#       remote-debugging / 9xxx 调试端口），就 arm —— 不管脚本叫什么、是不是这次刚写的。
#
# 两个让它安全又轻的性质（不变）：
#   1. 误触发无害 —— auto-allow 只在真有授权框时才点（scpt 三重校验），没框就空转后自退。
#      故匹配宁滥勿缺。
#   2. 绝大多数 bash 调用一条 grep 即否决；只有「跑脚本」那类命令才多读一个文件 grep 一遍。
#      永远快速 exit 0，绝不阻塞工具。
#
# 安装：在 ~/.claude/settings.json 的 PreToolUse → matcher "Bash" 的 hooks 里加一条
#       command 指向本脚本的绝对路径。

HERE="$(cd "$(dirname "$0")" && pwd)"
input="$(cat 2>/dev/null)"

arm() {
  # 诊断：仅在命中(arm)时记一行（不记非浏览器命令，无刷屏/隐私问题）
  snip="$(printf '%s' "$input" | tr '\n\t' '  ' | cut -c1-160)"
  printf '%s ARM | %s\n' "$(date '+%H:%M:%S')" "$snip" >> /tmp/cdp-auto-allow.hook.log 2>/dev/null
  "$HERE/on-demand.sh" watch 60 >/dev/null 2>&1 &
}

# (1) 命令文本直接含连接标记（含内联代码 / 命令里直接出现的端点；新增 DevToolsActivePort）
#     标记取连接专属信号，不取宽泛词，避免把 `git clone …chrome-devtools…` 之类也算上。
if printf '%s' "$input" | grep -qiE 'cdp-proxy|web-access|:?3456|/devtools/browser|remote-debugging|DevToolsActivePort'; then
  arm
  exit 0
fi

# (2) 命令跑了脚本文件 → 读脚本内容看它是否直连 Chrome（对 agent 动态生成、随机命名的脚本生效）。
#     从命令里抽出被执行的脚本路径（取第一个 .mjs/.cjs/.js/.ts/.py/.scpt）。
script="$(printf '%s' "$input" | grep -oE '(node|bun|deno|tsx|ts-node|python3?|osascript)[[:space:]]+[^[:space:]"'"'"']+\.(mjs|cjs|js|ts|py|scpt)' | grep -oE "[^[:space:]\"']+\.(mjs|cjs|js|ts|py|scpt)" | head -1)"
if [ -n "$script" ]; then
  # 相对路径：用命令里的 `cd DIR &&` 目录补全（agent 常 cd 到目录再跑脚本）。
  if [ "${script#/}" = "$script" ]; then
    cdir="$(printf '%s' "$input" | grep -oE 'cd[[:space:]]+[^[:space:]"'"'"'&;|]+' | head -1 | sed -E 's/^cd[[:space:]]+//')"
    [ -n "$cdir" ] && [ -f "$cdir/$script" ] && script="$cdir/$script"
  fi
  # 直连 Chrome 的代码特征：读 DevToolsActivePort / 连浏览器级 ws / json 探测 / 远程调试开关 / 9xxx 端口。
  if [ -f "$script" ] && grep -qiE 'DevToolsActivePort|/devtools/browser|/json/version|remote-debugging|127\.0\.0\.1:9[0-9]{3}|localhost:9[0-9]{3}' "$script" 2>/dev/null; then
    snip2="$(printf 'script-scan:%s' "$script" | cut -c1-160)"
    printf '%s ARM | %s\n' "$(date '+%H:%M:%S')" "$snip2" >> /tmp/cdp-auto-allow.hook.log 2>/dev/null
    "$HERE/on-demand.sh" watch 60 >/dev/null 2>&1 &
    exit 0
  fi
fi

exit 0
