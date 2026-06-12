#!/bin/bash
# 构建 Vibe.app(菜单栏应用)
# 用法: ./scripts/build-app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> swift build -c release"
swift build -c release

APP="build/Vibe.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp scripts/Info.plist "$APP/Contents/Info.plist"
cp .build/release/Vibe "$APP/Contents/MacOS/Vibe"

# Ad-hoc 签名(本机运行足够;分发需替换为开发者证书)
codesign --force --sign - "$APP"

echo ""
echo "✅ 构建完成: $APP"
echo "   首次启动会请求「系统音频录制」权限,请允许。"
echo "   打开方式: open $APP"
