#!/bin/bash
set -euo pipefail

pkill -f "/Applications/momi.app/Contents/MacOS/momi" 2>/dev/null || true
open /Applications/momi.app
echo "momi 已启动并在 Mac 顶部菜单栏显示！"
