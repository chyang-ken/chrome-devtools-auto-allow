#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$ROOT_DIR/CDP Auto Allow.app"
PLIST_SRC="$ROOT_DIR/launchd/com.local.cdp-auto-allow.plist"
PLIST_DST="$HOME/Library/LaunchAgents/com.local.cdp-auto-allow.plist"

mkdir -p "$HOME/Library/LaunchAgents"

osacompile -o "$APP_PATH" "$ROOT_DIR/scripts/cdp-auto-allow.scpt"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.local.CDPAutoAllow" "$APP_PATH/Contents/Info.plist" >/dev/null 2>&1 \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.local.CDPAutoAllow" "$APP_PATH/Contents/Info.plist"
codesign --force --sign - "$APP_PATH" >/dev/null 2>&1 || true

sed "s#__ROOT_DIR__#$ROOT_DIR#g" "$PLIST_SRC" > "$PLIST_DST"

launchctl unload "$PLIST_DST" >/dev/null 2>&1 || true
launchctl load "$PLIST_DST"

cat <<EOF
Installed and started:
  $PLIST_DST

Grant Accessibility permission to:
  $APP_PATH

Open:
  System Settings > Privacy & Security > Accessibility

Then add or enable "CDP Auto Allow".

Logs:
  /tmp/cdp-auto-allow.out.log
  /tmp/cdp-auto-allow.err.log
EOF
