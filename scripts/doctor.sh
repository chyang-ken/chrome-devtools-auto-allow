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
for s in agent-hook.sh conn-arm.sh on-demand.sh cdp-auto-allow.scpt; do
  if [[ -e "$ROOT_DIR/scripts/$s" ]]; then ok "$s 存在"; else bad "缺 scripts/$s"; fi
done

echo
bold "3. Chrome 进程"
if pgrep -f "/Google Chrome.app/Contents/MacOS/Google Chrome" >/dev/null; then
  ok "Google Chrome 在运行"
else
  warn "Google Chrome 没在运行（脚本本身没问题，但暂时也没东西可点）"
fi

echo
bold "4. /usr/bin/osascript 的 Accessibility 权限"
# Chrome 未激活时测一次
deactivate_result=$(/usr/bin/osascript <<'EOF' 2>&1
tell application "System Events"
  try
    if not (exists process "Google Chrome") then return "no-chrome"
    tell process "Google Chrome"
      try
        set n to count of (every window)
      on error e
        return "err:" & e
      end try
      return "count:" & n
    end tell
  on error e
    return "outer:" & e
  end try
end tell
EOF
)
# 激活 Chrome 后再测一次
activate_result=$(/usr/bin/osascript <<'EOF' 2>&1
tell application "Google Chrome" to activate
delay 0.5
tell application "System Events"
  try
    tell process "Google Chrome"
      try
        set n to count of (every window)
      on error e
        return "err:" & e
      end try
      return "count:" & n
    end tell
  on error e
    return "outer:" & e
  end try
end tell
EOF
)
case "$deactivate_result" in
  count:0) warn "Chrome 未激活时 count=0（正常，脚本会自动激活后重试）" ;;
  count:*) ok "Chrome 未激活时也能读到 ${deactivate_result#count:} 个窗口" ;;
  no-chrome) warn "Chrome 不在运行，没法测权限" ;;
  *) bad "调用 System Events 失败: $deactivate_result" ;;
esac
case "$activate_result" in
  count:0)
    bad "激活 Chrome 后仍 count=0 → 没有 Accessibility 权限"
    bad "  → System Settings > Privacy & Security > Accessibility"
    bad "  → 添加并启用 /usr/bin/osascript（点 +，按 Cmd+Shift+G 输入 /usr/bin/osascript）" ;;
  count:*) ok "激活 Chrome 后能读到 ${activate_result#count:} 个窗口 → 权限 OK" ;;
  *) bad "激活后调用 System Events 失败: $activate_result" ;;
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
echo "  - 想立刻验证:在 Chrome 里触发一次 CDP 连接（跑个连 Chrome 的脚本），再看 debug.log。"
echo "  - 实时跟随:tail -F $DEBUG_LOG"
echo "  - 触发日志:/tmp/cdp-auto-allow.hook.log（哪些命令 arm 了）+ /tmp/cdp-auto-allow.probe.log（探测器启动）"
