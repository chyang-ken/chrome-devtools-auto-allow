#!/usr/bin/env bash
# 兼容入口：实际多浏览器、多端口探测由 Node 实现，保持旧 hook 路径不变。
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
exec node "$HERE/conn-arm.mjs" "$@"
