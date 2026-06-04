#!/bin/bash
# Package ezclip as DMG
# Usage: ./Scripts/package-dmg.sh

set -e

cd "$(dirname "$0")/.."

APP_DIR="build/ezclip.app"
DMG_NAME="ezclip-1.0.0-arm64.dmg"
DMG_DIR="build/dmg"

if [ ! -d "${APP_DIR}" ]; then
    echo "❌ ${APP_DIR} not found. Run ./Scripts/build.sh first."
    exit 1
fi

echo "📦 Packaging DMG..."

rm -rf "${DMG_DIR}"
mkdir -p "${DMG_DIR}"

cp -R "${APP_DIR}" "${DMG_DIR}/"
ln -s /Applications "${DMG_DIR}/Applications"

hdiutil create \
    -volname "ezclip" \
    -srcfolder "${DMG_DIR}" \
    -ov \
    -format UDZO \
    "build/${DMG_NAME}"

echo ""
echo "✅ DMG created: build/${DMG_NAME}"
ls -lh "build/${DMG_NAME}"
echo ""
echo "   Open: open build/"
