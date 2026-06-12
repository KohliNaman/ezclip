#!/usr/bin/env bash
set -euo pipefail

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

DERIVED_DATA="${EZCLIP_DERIVED_DATA:-build/DerivedData}"
APP_PATH="${DERIVED_DATA}/Build/Products/Debug/ezclip.app"
INSTALL_PATH="/Applications/ezclip.app"
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

if command -v xcodegen >/dev/null 2>&1; then
    echo "==> Generating Xcode project"
    xcodegen generate
fi

echo "==> Building Debug arm64"
if [ "${#XCODE_SIGN_ARGS[@]}" -gt 0 ]; then
    xcodebuild build \
      -quiet \
      -project ezclip.xcodeproj \
      -scheme ezclip \
      -configuration Debug \
      -destination "platform=macOS,arch=arm64" \
      -derivedDataPath "$DERIVED_DATA" \
      "${XCODE_SIGN_ARGS[@]}"
else
    xcodebuild build \
      -quiet \
      -project ezclip.xcodeproj \
      -scheme ezclip \
      -configuration Debug \
      -destination "platform=macOS,arch=arm64" \
      -derivedDataPath "$DERIVED_DATA"
fi

if security find-identity -v -p codesigning | grep -Fq "\"${DEV_SIGN_IDENTITY}\""; then
    echo "==> Re-signing app with ${DEV_SIGN_IDENTITY}"
    codesign --force --deep --sign "${DEV_SIGN_IDENTITY}" --options runtime "$APP_PATH"
fi

echo "==> Installing to ${INSTALL_PATH}"
osascript -e 'tell application id "com.namaankohli.ezclip" to quit' >/dev/null 2>&1 || true
rm -rf "$INSTALL_PATH"
cp -R "$APP_PATH" "$INSTALL_PATH"
xattr -dr com.apple.quarantine "$INSTALL_PATH" 2>/dev/null || true
open "$INSTALL_PATH"
