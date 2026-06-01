#!/usr/bin/env bash
set -euo pipefail

PLIST_DST="$HOME/Library/LaunchAgents/com.local.cdp-auto-allow.plist"

launchctl unload "$PLIST_DST" >/dev/null 2>&1 || true
rm -f "$PLIST_DST"

cat <<EOF
Uninstalled LaunchAgent:
  $PLIST_DST

The generated app bundle is left in the project folder so macOS permissions remain inspectable.
Remove it manually if you no longer need it:
  CDP Auto Allow.app
EOF
