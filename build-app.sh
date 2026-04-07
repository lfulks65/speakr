#!/bin/bash
# Builds Speakr and packages it as a proper .app bundle.
# Usage:
#   ./build-app.sh          # debug build
#   ./build-app.sh release  # release build

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

CONFIG="${1:-debug}"
APP_NAME="Speakr"
APP_BUNDLE="${APP_NAME}.app"
BUILD_DIR=".build/${CONFIG}"
BINARY="${BUILD_DIR}/${APP_NAME}"
BUNDLE_DIR="${BUILD_DIR}/${APP_BUNDLE}"

echo "▶ Building ${APP_NAME} (${CONFIG})..."
if [ "$CONFIG" = "release" ]; then
    swift build -c release
else
    swift build
fi

echo "▶ Creating .app bundle at ${BUNDLE_DIR}..."
rm -rf "${BUNDLE_DIR}"
mkdir -p "${BUNDLE_DIR}/Contents/MacOS"
mkdir -p "${BUNDLE_DIR}/Contents/Resources"

# Copy binary
cp "${BINARY}" "${BUNDLE_DIR}/Contents/MacOS/${APP_NAME}"

# Copy Info.plist
cp "Resources/Info.plist" "${BUNDLE_DIR}/Contents/Info.plist"

# Ad-hoc codesign with hardened runtime so Gatekeeper is less aggressive.
echo "▶ Codesigning (ad-hoc, hardened runtime)..."
codesign --deep --force --sign - \
    --options runtime \
    --entitlements "Resources/Speakr.entitlements" \
    "${BUNDLE_DIR}"

# Strip quarantine attribute so the app opens without Gatekeeper warnings.
xattr -cr "${BUNDLE_DIR}"

# Install to /Applications so macOS can find it in permission dialogs
echo "▶ Installing to /Applications..."
pkill -x "${APP_NAME}" 2>/dev/null || true
sleep 0.5
cp -R "${BUNDLE_DIR}" "/Applications/${APP_BUNDLE}"

# Reset app settings so updated defaults (autoPaste=true, etc.) take effect
echo "▶ Resetting stored settings to apply new defaults..."
defaults delete com.speakr.app 2>/dev/null || true

echo ""
echo "✅ Done! Installed to /Applications/${APP_BUNDLE}"
echo ""
echo "To run:  open '/Applications/${APP_BUNDLE}'"
echo ""
echo "If this is the first launch, Speakr will ask for Accessibility"
echo "permission automatically. Click 'Open System Settings' in the dialog"
echo "and toggle Speakr on in the Accessibility list."
