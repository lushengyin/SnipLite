#!/bin/bash
# 生成工程 → 构建 → 启动。用法：
#   ./run.sh              构建并启动
#   ./run.sh --capture    启动后立刻进入截图
set -euo pipefail
cd "$(dirname "$0")"

xcodegen generate >/dev/null

# 固定签名身份，避免每次重编译后屏幕录制权限失效
KEYCHAIN="$HOME/Library/Keychains/sniplite-signing.keychain-db"
if [ -f "$KEYCHAIN" ]; then
  security unlock-keychain -p sniplite "$KEYCHAIN" >/dev/null 2>&1 || true
fi

xcodebuild -project SnipLite.xcodeproj -scheme SnipLite -configuration Debug build >/tmp/sniplite-build.log 2>&1 || {
  echo "构建失败，日志：/tmp/sniplite-build.log"
  grep -E "error:" /tmp/sniplite-build.log | head -20
  exit 1
}

APP="$HOME/Library/Developer/Xcode/DerivedData/SnipLite-bxwxgdiypmyduhdmfvjysrprrpkt/Build/Products/Debug/SnipLite.app"
if [ ! -d "$APP" ]; then
  APP=$(find "$HOME/Library/Developer/Xcode/DerivedData" -maxdepth 4 -name "SnipLite.app" -path "*Debug*" | head -1)
fi

pkill -f "SnipLite.app/Contents/MacOS/SnipLite" 2>/dev/null || true
sleep 0.3
if [ $# -eq 0 ]; then
  open "$APP"
else
  open "$APP" --args "$@"
fi
echo "已启动：$APP"
echo "按 ⌃⌥A 截图（状态栏图标可能被 Ice 收进隐藏区）"
