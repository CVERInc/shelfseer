#!/bin/bash
# Build the native SwiftUI shelfseer.app using Command Line Tools only (no Xcode).
# The macOS app is a SwiftPM package (depends on Signet), so this builds via
# `swift build` and bundles the release binary into a double-clickable .app.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"        # app/scripts
PACKAGE_DIR="$(cd "$DIR/.." && pwd)"        # app/ (the SwiftPM package)
BUILD_DIR="$PACKAGE_DIR/build"
APP="$BUILD_DIR/shelfseer.app"

echo "→ Cleaning previous build"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "→ Building (SwiftPM release)"
( cd "$PACKAGE_DIR" && swift build -c release --product ShelfseerApp )
# Bundle executable name matches Info.plist's CFBundleExecutable.
cp "$PACKAGE_DIR/.build/release/ShelfseerApp" "$APP/Contents/MacOS/ShelfseerApp"

echo "→ Assembling bundle"
cp "$PACKAGE_DIR/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "→ Ad-hoc code signing"
xattr -cr "$APP"
codesign --force --sign - "$APP"

echo "✓ Built: $APP"
echo "  Double-click it in Finder (first time: right-click → Open if macOS warns it's unsigned)."
