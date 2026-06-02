#!/usr/bin/env bash
# 一键自检：判断 cdp-auto-allow 为什么没生效。
set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCPT="$ROOT_DIR/scripts/cdp-auto-allow.scpt"
PLIST="$HOME/Library/LaunchAgents/com.local.cdp-auto-allow.plist"
DEBUG_LOG="/tmp/cdp-auto-allow.debug.log"
ERR_LOG="/tmp/cdp-auto-allow.err.log"

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; }

bold "1. LaunchAgent"
if launchctl list com.local.cdp-auto-allow >/dev/null 2>&1; then
  PID=$(launchctl list com.local.cdp-auto-allow | awk -F'=' '/"PID"/{gsub(/[^0-9]/,"",$2);print $2}')
  STATUS=$(launchctl list com.local.cdp-auto-allow | awk -F'=' '/LastExitStatus/{gsub(/[^0-9-]/,"",$2);print $2}')
  if [[ -n "$PID" && "$PID" != "0" ]]; then
    ok "服务在运行 PID=$PID"
  else
    bad "服务已注册但没在运行 (LastExitStatus=$STATUS)"
  fi
else
  bad "未注册 LaunchAgent，先运行 scripts/install.sh"
fi

if [[ -f "$PLIST" ]]; then
  ok "plist: $PLIST"
else
  bad "缺少 $PLIST"
fi

echo
bold "2. Chrome 进程"
if pgrep -f "/Google Chrome.app/Contents/MacOS/Google Chrome" >/dev/null; then
  ok "Google Chrome 在运行"
else
  warn "Google Chrome 没在运行（脚本本身没问题，但暂时也没东西可点）"
fi

echo
bold "3. /usr/bin/osascript 的 Accessibility 权限"

# 先测试 Chrome 未激活时
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

# 再激活 Chrome 后测试
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
  count:0)
    warn "Chrome 未激活时 count=0（正常现象，脚本会自动激活后重试）"
    ;;
  count:*)
    ok "Chrome 未激活时也能读到 ${deactivate_result#count:} 个窗口"
    ;;
  no-chrome)
    warn "Chrome 不在运行，没法测权限"
    ;;
  *)
    bad "调用 System Events 失败: $deactivate_result"
    ;;
esac

case "$activate_result" in
  count:0)
    bad "激活 Chrome 后仍 count=0 → 没有 Accessibility 权限"
    bad "  → 请到 System Settings > Privacy & Security > Accessibility"
    bad "  → 添加并启用 /usr/bin/osascript（点 +，按 Cmd+Shift+G 输入 /usr/bin/osascript）"
    ;;
  count:*)
    ok "激活 Chrome 后能读到 ${activate_result#count:} 个窗口 → 权限 OK"
    ;;
  *)
    bad "激活后调用 System Events 失败: $activate_result"
    ;;
esac

echo
bold "4. 当前最新日志（debug.log）"
if [[ -s "$DEBUG_LOG" ]]; then
  tail -n 15 "$DEBUG_LOG" | sed 's/^/  /'
else
  warn "$DEBUG_LOG 为空（脚本要么没跑，要么权限被拒后 do shell script 也写不进）"
fi

echo
bold "5. err.log"
if [[ -s "$ERR_LOG" ]]; then
  tail -n 5 "$ERR_LOG" | sed 's/^/  /'
else
  ok "err.log 为空（没有 -1728 之类错误）"
fi

echo
bold "提示"
echo "  - 弹窗出现时脚本会尝试两种方式："
echo "    1) 读取弹窗文本并点击 Allow 按钮"
echo "    2) 如果弹窗是 Chrome 内部渲染的对话框（AXUnknown + 小尺寸），"
echo "       脚本会激活 Chrome 并发送 Return 键点击默认 Allow 按钮"
echo "  - 想立刻验证：在 Chrome 里触发一次 CDP 连接，"
echo "    然后跑 ./scripts/doctor.sh 看 debug.log"
echo "  - 实时跟随日志：tail -F $DEBUG_LOG"
