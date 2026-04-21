#!/bin/bash
# Build a release .app bundle and zip it for distribution.
#
# Usage: scripts/package-release.sh [VERSION]
#   VERSION defaults to the latest `vX.Y.Z` git tag, or "0.0.0" if none exist.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build"
APP_DIR="$BUILD_DIR/BubbleDuck.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"
ZIP_PATH="$BUILD_DIR/BubbleDuck-macOS-arm64.zip"

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    VERSION="$(git -C "$PROJECT_DIR" describe --tags --abbrev=0 --match 'v*' 2>/dev/null | sed 's/^v//' || true)"
fi
VERSION="${VERSION:-0.0.0}"

echo "Building BubbleDuck $VERSION (release)..."
cd "$PROJECT_DIR"
swift build -c release

echo "Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BUILD_DIR/release/BubbleDuck" "$MACOS_DIR/BubbleDuck"
chmod +x "$MACOS_DIR/BubbleDuck"

cat > "$CONTENTS/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>BubbleDuck</string>
    <key>CFBundleIdentifier</key>
    <string>com.bubbleduck.app</string>
    <key>CFBundleName</key>
    <string>BubbleDuck</string>
    <key>CFBundleDisplayName</key>
    <string>BubbleDuck</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSUIElement</key>
    <false/>
</dict>
</plist>
PLIST

echo "Ad-hoc codesigning..."
# Without at least an ad-hoc signature, macOS Gatekeeper marks the bundle
# "damaged and can't be opened" after download, even with quarantine cleared.
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

echo "Creating zip..."
rm -f "$ZIP_PATH"
# `ditto -c -k --sequesterRsrc --keepParent` is Apple's recommended tool for
# archiving app bundles — plain `zip` loses extended attributes / exec bits
# and has produced "damaged" download reports in the past.
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

echo ""
echo "Release artifact: $ZIP_PATH"
echo "Version: $VERSION"
ls -lh "$ZIP_PATH"
