#!/bin/bash
# 一键构建 电脑不休眠.app（需要 Xcode Command Line Tools：xcode-select --install）
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="电脑不休眠"
EXEC="KeepAwake"
BUNDLE="$APP_NAME.app"

command -v swiftc >/dev/null || { echo "缺少 swiftc：请先运行 xcode-select --install"; exit 1; }

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

echo "→ 编译 $EXEC ..."
swiftc -O -swift-version 5 app/main.swift -o "$BUNDLE/Contents/MacOS/$EXEC"

cp app/Info.plist "$BUNDLE/Contents/Info.plist"
cp assets/AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"

echo "→ 临时签名 ..."
codesign --force --deep -s - "$BUNDLE" >/dev/null 2>&1 || echo "  （签名跳过，不影响本机运行）"

echo "✅ 已生成 $BUNDLE"
echo "   直接双击即可；要装到桌面：mv \"$BUNDLE\" ~/Desktop/"
