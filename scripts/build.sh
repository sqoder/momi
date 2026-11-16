#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$DIR/build/momi.app"
BUNDLE_EXEC="/Applications/momi.app/Contents/MacOS/momi"
ARCH="$(uname -m)"
SIGN_IDENTITY="${MOMI_SIGN_IDENTITY:--}"

echo "==> 正在编译 momi.app (${ARCH})..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$DIR/src/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$DIR/resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp "$DIR"/resources/agents/*.png "$APP_DIR/Contents/Resources/"

SWIFT_SOURCES=(
    "$DIR"/src/App/*.swift
    "$DIR"/src/Core/*.swift
    "$DIR"/src/Readers/*.swift
    "$DIR"/src/UI/*.swift
)

swiftc -O -target "${ARCH}-apple-macos13.0" "${SWIFT_SOURCES[@]}" -o "$APP_DIR/Contents/MacOS/momi"

if [ "$SIGN_IDENTITY" != "-" ]; then
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_DIR"
else
    codesign --force --sign - "$APP_DIR"
fi

echo "==> 安装至 /Applications/momi.app..."
pkill -f "$BUNDLE_EXEC" 2>/dev/null || true
rm -rf /Applications/momi.app
cp -R "$APP_DIR" /Applications/momi.app

# 未签名时系统会拒绝托管菜单栏项（spctl: code has no resources）
if [ "$SIGN_IDENTITY" != "-" ]; then
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" /Applications/momi.app
else
    codesign --force --sign - /Applications/momi.app
fi

echo "==> 编译完成！已安装到 /Applications/momi.app"
