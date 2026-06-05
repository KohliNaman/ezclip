#!/usr/bin/env bash
set -euo pipefail

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
ARCHIVE_PATH="build/ezclip.xcarchive"
APP_PATH="build/ezclip.app"
DMG_PATH="build/ezclip-v${VERSION}.dmg"

echo "==> Building ezclip v${VERSION}"

# Clean
rm -rf build/
mkdir -p build/

# Generate Xcode project
if command -v xcodegen &> /dev/null; then
    echo "==> Generating Xcode project"
    xcodegen generate
fi

# Archive (universal binary, release config)
echo "==> Archiving"
xcodebuild archive \
  -project ezclip.xcodeproj \
  -scheme ezclip \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  ONLY_ACTIVE_ARCH=NO

# Export .app from archive
echo "==> Exporting .app"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath build/ \
  -exportOptionsPlist Scripts/ExportOptions.plist

# Package as DMG
if command -v create-dmg &> /dev/null; then
    echo "==> Creating DMG"
    create-dmg \
      --volname "ezclip" \
      --window-pos 200 120 \
      --window-size 660 400 \
      --icon-size 160 \
      --icon "ezclip.app" 180 170 \
      --hide-extension "ezclip.app" \
      --app-drop-link 480 170 \
      --no-internet-enable \
      "$DMG_PATH" \
      "$APP_PATH"
else
    echo "==> create-dmg not installed — making simple DMG"
    mkdir -p build/dmg
    cp -R "$APP_PATH" build/dmg/
    ln -s /Applications build/dmg/Applications
    hdiutil create -volname "ezclip" -srcfolder build/dmg -ov -format UDZO "$DMG_PATH"
fi

echo "==> Done: $DMG_PATH"
ls -lh "$DMG_PATH"
