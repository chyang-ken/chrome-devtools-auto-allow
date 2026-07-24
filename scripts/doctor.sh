#!/usr/bin/env bash
# 一键自检:判断 cdp-auto-allow（连接感知 / hook 按需模式）为什么没生效。
set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$ROOT_DIR/scripts/agent-hook.sh"
DEBUG_LOG="/tmp/cdp-auto-allow.debug.log"

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; }

bold "1. PreToolUse hook 是否注册到 agent"
for pair in "Claude Code|$HOME/.claude/settings.json" "Codex|$HOME/.codex/hooks.json"; do
  name="${pair%%|*}"; f="${pair#*|}"
  if [[ -f "$f" ]] && grep -q 'agent-hook.sh' "$f" 2>/dev/null; then
    ok "$name 已注册 ($f)"
  else
    bad "$name 未注册 → 运行 scripts/install.sh"
  fi
done

echo
bold "2. 依赖 + 脚本可执行位"
for dep in node lsof osascript; do
  if command -v "$dep" >/dev/null 2>&1; then ok "$dep 可用"; else bad "缺 $dep"; fi
done
for s in agent-hook.sh hook-decision.mjs browser-targets.mjs conn-arm.sh conn-arm.mjs on-demand.sh cdp-auto-allow.scpt; do
  if [[ -e "$ROOT_DIR/scripts/$s" ]]; then ok "$s 存在"; else bad "缺 scripts/$s"; fi
done

echo
bold "3. macOS Chromium 浏览器家族"
installed=0
for pair in \
  "Google Chrome|/Applications/Google Chrome.app" \
  "Google Chrome Beta|/Applications/Google Chrome Beta.app" \
  "Google Chrome Dev|/Applications/Google Chrome Dev.app" \
  "Google Chrome Canary|/Applications/Google Chrome Canary.app" \
  "Chromium|/Applications/Chromium.app" \
  "Microsoft Edge|/Applications/Microsoft Edge.app" \
  "Microsoft Edge Beta|/Applications/Microsoft Edge Beta.app" \
  "Microsoft Edge Dev|/Applications/Microsoft Edge Dev.app" \
  "Microsoft Edge Canary|/Applications/Microsoft Edge Canary.app"; do
  name="${pair%%|*}"; app="${pair#*|}"
  if [[ -d "$app" ]]; then ok "$name 已安装"; installed=$((installed+1)); fi
done
if [[ "$installed" = 0 ]]; then
  warn "未发现受支持浏览器"
fi

targets="$(node "$ROOT_DIR/scripts/browser-targets.mjs" 2>/dev/null)"
if [[ -n "$targets" ]]; then
  while IFS= read -r target; do
    ok "发现真实调试入口: $target"
  done <<< "$targets"
else
  warn "当前没有受支持浏览器开放调试端口（空闲时是正常状态）"
fi

echo
bold "4. /usr/bin/osascript 的 Accessibility 权限"
access_result=$(/usr/bin/osascript -e 'tell application "System Events" to get UI elements enabled' 2>&1)
case "$access_result" in
  true) ok "Accessibility 权限 OK" ;;
  *)
    bad "无法使用 Accessibility: $access_result"
    bad "  → System Settings > Privacy & Security > Accessibility"
    bad "  → 添加并启用 /usr/bin/osascript（点 +，按 Cmd+Shift+G 输入 /usr/bin/osascript）" ;;
esac

echo
bold "5. 当前看守状态（按需，stopped 是常态）"
"$ROOT_DIR/scripts/on-demand.sh" status 2>/dev/null | sed 's/^/  /'

echo
bold "6. 最新诊断日志（debug.log）"
if [[ -s "$DEBUG_LOG" ]]; then
  tail -n 12 "$DEBUG_LOG" | sed 's/^/  /'
else
  warn "$DEBUG_LOG 为空（还没触发过，或权限被拒后 do shell script 也写不进）"
fi

echo
bold "提示"
echo "  - 想立刻验证:在任一受支持浏览器里触发一次 CDP 连接，再看 debug.log。"
echo "  - 实时跟随:tail -F $DEBUG_LOG"
echo "  - 触发日志:/tmp/cdp-auto-allow.hook.log（哪些命令 arm 了）+ /tmp/cdp-auto-allow.probe.log（探测器启动）"
