#!/bin/bash
# 打包 Vibe.app 为 DMG
# 用法: ./scripts/package-dmg.sh
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Vibe.app"
DIST="dist"
DMG_ROOT="$DIST/dmgroot"
DMG="$DIST/Vibe.dmg"
VOLUME_NAME="Vibe"

echo "==> 构建 app"
./scripts/build-app.sh

echo "==> 准备 DMG 目录"
rm -rf "$DMG_ROOT"
mkdir -p "$DMG_ROOT" "$DIST"

cp -R "$APP" "$DMG_ROOT/"
ln -s /Applications "$DMG_ROOT/Applications"

cat > "$DMG_ROOT/使用说明.txt" <<'EOF'
Vibe 使用说明

1. 将 Vibe.app 拖到 Applications 文件夹。
2. 打开 Vibe。
3. 首次运行时,请在系统提示中允许「系统音频录制」权限。
   如果没有看到弹窗,可以到:
   系统设置 → 隐私与安全性 → 屏幕录制与系统音频录制
   手动允许 Vibe,然后重新打开。

如果 macOS 提示无法打开、来自身份不明的开发者,或提示 app 已损坏,请打开「终端」执行:

xattr -dr com.apple.quarantine /Applications/Vibe.app

然后重新打开 Vibe。

注意:
- 需要 macOS 14.4 或更高版本。
- 当前版本使用 ad-hoc 签名,适合自用或测试分发。
EOF

echo "==> 创建 DMG: $DMG"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$DMG"

echo "==> 验证 DMG"
hdiutil verify "$DMG"

echo ""
echo "✅ 打包完成: $DMG"
echo "   注意: 内部 app 仍是 ad-hoc 签名,适合自用/测试分发。"
