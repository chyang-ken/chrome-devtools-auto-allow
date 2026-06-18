#!/usr/bin/env bash
# 卸载:① 从 Claude Code + Codex 配置移除本 hook;② 清掉旧版可能装过的常驻 LaunchAgent;
#        ③ 停掉当前看守。
set -uo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$ROOT_DIR/scripts/agent-hook.sh"

echo "① 移除 PreToolUse hook:"
if command -v node >/dev/null 2>&1; then
  node "$ROOT_DIR/scripts/register-hooks.mjs" remove "$HOOK" || true
else
  echo "  (无 node,跳过——请手动从 ~/.claude/settings.json 和 ~/.codex/hooks.json 删除指向 agent-hook.sh 的 hook 项)"
fi

# ② 兼容:清掉旧版可能装过的常驻 LaunchAgent
PLIST="$HOME/Library/LaunchAgents/com.local.cdp-auto-allow.plist"
if [[ -f "$PLIST" ]]; then
  launchctl unload "$PLIST" >/dev/null 2>&1 || true
  rm -f "$PLIST"
  echo "② 已清除旧 LaunchAgent: $PLIST"
fi

# ③ 停掉当前看守
"$ROOT_DIR/scripts/on-demand.sh" stop >/dev/null 2>&1 || true

echo "完成。Accessibility 权限若不再需要,可自行在 System Settings 里移除 /usr/bin/osascript。"
