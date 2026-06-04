#!/bin/bash
# Build ezclip locally on macOS
# Usage: ./Scripts/build.sh

set -e

cd "$(dirname "$0")/.."

echo "🏗️  Building ezclip..."

# Build Swift package
swift build -c release --arch arm64

# Create .app bundle
APP_NAME="ezclip"
BUILD_BIN=".build/arm64-apple-macosx/release/${APP_NAME}"
APP_DIR="build/${APP_NAME}.app"
CONTENTS="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
RESOURCES_DIR="${CONTENTS}/Resources"

rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# Copy binary
cp "${BUILD_BIN}" "${MACOS_DIR}/${APP_NAME}"
chmod +x "${MACOS_DIR}/${APP_NAME}"

# Info.plist
cat > "${CONTENTS}/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ezclip</string>
    <key>CFBundleIdentifier</key>
    <string>com.ezclip.app</string>
    <key>CFBundleName</key>
    <string>ezclip</string>
    <key>CFBundleDisplayName</key>
    <string>ezclip</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <false/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>MIT License. Context-aware screenshot curation.</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>ezclip captures screenshots of your frontmost window when you double-press ⌘.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>ezclip uses AppleScript to read context (URL, song name) from apps.</string>
</dict>
</plist>
PLIST

echo ""
echo "✅ Build complete: ${APP_DIR}"
echo "   Run: open build/"
echo ""
echo "   Or to create DMG:"
echo "   ./Scripts/package-dmg.sh"
