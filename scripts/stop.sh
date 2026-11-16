#!/bin/bash
set -euo pipefail

pkill -f "/Applications/momi.app/Contents/MacOS/momi" 2>/dev/null || true
echo "momi 已退出！"
