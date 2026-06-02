#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PLIST_SRC="$ROOT_DIR/launchd/com.local.cdp-auto-allow.plist"
PLIST_DST="$HOME/Library/LaunchAgents/com.local.cdp-auto-allow.plist"

mkdir -p "$HOME/Library/LaunchAgents"

sed "s#__ROOT_DIR__#$ROOT_DIR#g" "$PLIST_SRC" > "$PLIST_DST"

launchctl unload "$PLIST_DST" >/dev/null 2>&1 || true
launchctl load "$PLIST_DST"

cat <<EOF
Installed and started:
  $PLIST_DST

Grant Accessibility permission to:
  /usr/bin/osascript

Open:
  System Settings > Privacy & Security > Accessibility

Then add or enable "osascript" (or "Script Editor" / "Terminal",
whichever macOS surfaces — the one that's actually executing
$ROOT_DIR/scripts/cdp-auto-allow.scpt under your account).

Logs:
  /tmp/cdp-auto-allow.out.log
  /tmp/cdp-auto-allow.err.log

Uninstall:
  $ROOT_DIR/scripts/uninstall.sh
EOF
