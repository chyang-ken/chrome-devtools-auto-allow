#!/usr/bin/env bash
# 安装 cdp-auto-allow（连接感知 / PreToolUse hook 按需模式）。
#
# 做两件事:
#   ① 把 agent-hook.sh 注册成 Claude Code + Codex 的 PreToolUse hook（幂等、自动）。
#   ② 提示授予 /usr/bin/osascript 的 Accessibility 权限（scpt 点「允许」框需要）。
#
# 注意:本版不再装 7×24 常驻 LaunchAgent —— 改用 hook 按需点火、用完即收
#      （详见 README「为什么不用常驻」）。如确实需要无 agent 的常驻兜底,见 launchd/ 目录。
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$ROOT_DIR/scripts/agent-hook.sh"

# 关键脚本统统加可执行位
chmod +x "$ROOT_DIR"/scripts/agent-hook.sh "$ROOT_DIR"/scripts/conn-arm.sh \
         "$ROOT_DIR"/scripts/on-demand.sh "$ROOT_DIR"/scripts/doctor.sh \
         "$ROOT_DIR"/scripts/uninstall.sh 2>/dev/null || true

if ! command -v node >/dev/null 2>&1; then
  echo "✗ 需要 node 来注册 hook（这本就是给 Claude Code / Codex 用户的工具，应已具备）。" >&2
  exit 1
fi

echo "① 注册 PreToolUse hook（幂等）:"
node "$ROOT_DIR/scripts/register-hooks.mjs" add "$HOOK"

cat <<EOF

② 授予 Accessibility 权限（scpt 点「允许」框需要，只需一次）:
   System Settings > Privacy & Security > Accessibility
   添加并启用 /usr/bin/osascript（点 +，按 Cmd+Shift+G 输入 /usr/bin/osascript）

完成后跑自检确认一切就位:
   $ROOT_DIR/scripts/doctor.sh

卸载:
   $ROOT_DIR/scripts/uninstall.sh
EOF
