#!/bin/bash
# 打 Release 包并生成 dmg。
# 用法：./package.sh
set -euo pipefail
cd "$(dirname "$0")"

xcodegen generate >/dev/null

KEYCHAIN="$HOME/Library/Keychains/sniplite-signing.keychain-db"
if [ -f "$KEYCHAIN" ]; then
  security unlock-keychain -p sniplite "$KEYCHAIN" >/dev/null 2>&1 || true
fi

xcodebuild -project SnipLite.xcodeproj -scheme SnipLite -configuration Release build >/tmp/sniplite-release.log 2>&1 || {
  echo "Release 构建失败，日志：/tmp/sniplite-release.log"
  grep -E "error:" /tmp/sniplite-release.log | head -20
  exit 1
}

APP=$(find "$HOME/Library/Developer/Xcode/DerivedData" -maxdepth 6 -name "SnipLite.app" -path "*Release*" | head -1)
if [ -z "$APP" ]; then
  echo "找不到 Release 产物"
  exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
OUT="build"
rm -rf "$OUT/dmg"
mkdir -p "$OUT/dmg" "$OUT"
cp -R "$APP" "$OUT/dmg/"

hdiutil create -volname "SnipLite $VERSION" -srcfolder "$OUT/dmg" -ov -format UDZO \
  "$OUT/SnipLite-$VERSION.dmg" >/dev/null

echo "已生成：$OUT/SnipLite-$VERSION.dmg"
echo
echo "签名：$(codesign -dvv "$APP" 2>&1 | grep Authority | head -1)"
echo "如需分发，请用 Developer ID 证书重签并公证："
echo "  codesign --deep --force --options runtime --sign \"Developer ID Application: ...\" \"$APP\""
echo "  xcrun notarytool submit \"$OUT/SnipLite-$VERSION.dmg\" --apple-id ... --team-id ... --password ... --wait"
echo "  xcrun stapler staple \"$OUT/SnipLite-$VERSION.dmg\""
