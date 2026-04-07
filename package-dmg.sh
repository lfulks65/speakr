#!/bin/bash
# Builds a release .app bundle and packages it into a distributable .dmg
# Usage: ./package-dmg.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="Speakr"
VERSION=$(grep -A1 CFBundleShortVersionString Resources/Info.plist | grep string | sed 's/.*<string>\(.*\)<\/string>/\1/')
DMG_NAME="${APP_NAME}-${VERSION}"
BUILD_DIR=".build/release"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
DMG_STAGING=".build/dmg-staging"
DMG_OUTPUT="${DMG_NAME}.dmg"

echo "▶ Building ${APP_NAME} v${VERSION} (release)..."
swift build -c release

echo "▶ Creating .app bundle..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"

# Strip debug symbols for smaller binary
strip -x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}" 2>/dev/null || true

echo "▶ Codesigning (ad-hoc, hardened runtime)..."
codesign --deep --force --sign - \
    --options runtime \
    --entitlements "Resources/Speakr.entitlements" \
    "${APP_BUNDLE}"

# Strip quarantine so the app opens without Gatekeeper warnings when
# installed from the DMG.
xattr -cr "${APP_BUNDLE}"

echo "▶ Creating DMG..."
rm -rf "${DMG_STAGING}"
mkdir -p "${DMG_STAGING}"

# Copy the .app into staging
cp -R "${APP_BUNDLE}" "${DMG_STAGING}/${APP_NAME}.app"

# Create symlink to /Applications for drag-to-install
ln -s /Applications "${DMG_STAGING}/Applications"

# Remove any previous DMG
rm -f "${DMG_OUTPUT}"

# Create the DMG
hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${DMG_STAGING}" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "${DMG_OUTPUT}"

# Clean up staging
rm -rf "${DMG_STAGING}"

# Show result
DMG_SIZE=$(du -h "${DMG_OUTPUT}" | cut -f1)
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ ${DMG_OUTPUT} (${DMG_SIZE})"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "To install: open the DMG and drag Speakr to Applications."
echo "First launch will prompt for Microphone and Accessibility permissions."
