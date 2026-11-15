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

APP=$(xcodebuild -project SnipLite.xcodeproj -scheme SnipLite -configuration Release \
  -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ TARGET_BUILD_DIR /{dir=$2} / FULL_PRODUCT_NAME /{name=$2} END{print dir "/" name}')
if [ ! -d "$APP" ]; then
  echo "找不到 Release 产物：$APP"
  exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
OUT="build"
VOLNAME="SnipLite $VERSION"
DMG="$OUT/SnipLite-$VERSION.dmg"
STAGE="$OUT/dmg"
RW_DMG="$OUT/SnipLite-$VERSION-rw.dmg"

rm -rf "$STAGE" "$DMG" "$RW_DMG"
mkdir -p "$STAGE" "$OUT"
cp -R "$APP" "$STAGE/"
# 提供拖拽目标：Finder 里显示为 Applications 文件夹快捷方式
ln -s /Applications "$STAGE/Applications"

# 先建可读写镜像，排好图标位置后再压缩，双击打开才是标准的拖动安装界面
# 同名卷已挂载时 hdiutil 会加 " 1" 后缀，且 Finder 脚本会认错盘，先清掉
if [ -d "/Volumes/$VOLNAME" ]; then
  hdiutil detach "/Volumes/$VOLNAME" -force -quiet 2>/dev/null || true
fi
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -ov -format UDRW -fs HFS+ "$RW_DMG" >/dev/null

MNT=$(hdiutil attach "$RW_DMG" -noautoopen -nobrowse -readwrite \
  | awk -F'\t' 'END{print $3}')

# 布局依赖 Finder 自动化，失败时至少保留 Applications 快捷方式
APPNAME=$(basename "$APP")
osascript <<EOF >/dev/null 2>&1 || true
tell application "Finder"
  tell disk "$VOLNAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {200, 140, 800, 540}
    set opts to icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set position of item "$APPNAME" of container window to {150, 190}
    set position of item "Applications" of container window to {450, 190}
    close
    open
    update without registering applications
    delay 1
    close
  end tell
end tell
EOF

sleep 1
hdiutil detach "$MNT" -quiet 2>/dev/null || hdiutil detach "$MNT" -force -quiet
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
rm -f "$RW_DMG"

echo "已生成：$DMG"
echo
echo "签名：$(codesign -dvv "$APP" 2>&1 | grep Authority | head -1)"
echo "如需分发，请用 Developer ID 证书重签并公证："
echo "  codesign --deep --force --options runtime --sign \"Developer ID Application: ...\" \"$APP\""
echo "  xcrun notarytool submit \"$OUT/SnipLite-$VERSION.dmg\" --apple-id ... --team-id ... --password ... --wait"
echo "  xcrun stapler staple \"$OUT/SnipLite-$VERSION.dmg\""
