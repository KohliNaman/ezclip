#!/usr/bin/env bash
set -euo pipefail

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
ARCHIVE_PATH="build/ezclip.xcarchive"
APP_PATH="build/ezclip.app"
DMG_PATH="build/ezclip-v${VERSION}.dmg"
DEV_SIGN_IDENTITY="${EZCLIP_DEV_SIGN_IDENTITY:-ezclip dev}"
XCODE_SIGN_ARGS=()

if security find-identity -v -p codesigning | grep -Fq "\"${DEV_SIGN_IDENTITY}\""; then
    echo "==> Using persistent local signing identity: ${DEV_SIGN_IDENTITY}"
    XCODE_SIGN_ARGS=(
      CODE_SIGN_STYLE=Manual
      DEVELOPMENT_TEAM=
      CODE_SIGN_IDENTITY="${DEV_SIGN_IDENTITY}"
      OTHER_CODE_SIGN_FLAGS=--options=runtime
    )
else
    echo "==> Persistent signing identity '${DEV_SIGN_IDENTITY}' not found; using project signing defaults"
fi

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
if [ "${#XCODE_SIGN_ARGS[@]}" -gt 0 ]; then
    xcodebuild archive \
      -project ezclip.xcodeproj \
      -scheme ezclip \
      -configuration Release \
      -archivePath "$ARCHIVE_PATH" \
      ONLY_ACTIVE_ARCH=NO \
      "${XCODE_SIGN_ARGS[@]}"
else
    xcodebuild archive \
      -project ezclip.xcodeproj \
      -scheme ezclip \
      -configuration Release \
      -archivePath "$ARCHIVE_PATH" \
      ONLY_ACTIVE_ARCH=NO
fi

# Export .app from archive
echo "==> Exporting .app"
if ! xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath build/ \
    -exportOptionsPlist Scripts/ExportOptions.plist; then
    echo "==> Developer ID export failed; using archived app for local DMG"
    rm -rf "$APP_PATH"
    cp -R "$ARCHIVE_PATH/Products/Applications/ezclip.app" "$APP_PATH"
fi

if security find-identity -v -p codesigning | grep -Fq "\"${DEV_SIGN_IDENTITY}\""; then
    echo "==> Re-signing local app with ${DEV_SIGN_IDENTITY}"
    codesign --force --deep --sign "${DEV_SIGN_IDENTITY}" --options runtime "$APP_PATH"
fi

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
