#!/bin/sh
# Builds an ad-hoc signed Release Glance.app and packages it as dist/Glance-<version>.dmg.
set -eu

cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

BUILD=build
DIST=dist
APP="$BUILD/Build/Products/Release/Glance.app"

xcodebuild -project Glance.xcodeproj -scheme Glance -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$BUILD" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= \
  ENABLE_HARDENED_RUNTIME=YES build | grep -E '^(\*\*|error|warning: .*error)' || true

[ -d "$APP" ] || { echo "Build failed: $APP not found" >&2; exit 1; }
codesign --verify --deep --strict "$APP"

VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
DMG="$DIST/Glance-$VERSION.dmg"

rm -rf "$DIST/dmg" "$DMG"
mkdir -p "$DIST/dmg"
cp -R "$APP" "$DIST/dmg/"
ln -s /Applications "$DIST/dmg/Applications"
hdiutil create -volname "Glance" -srcfolder "$DIST/dmg" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$DIST/dmg"

echo "Created $DMG ($(du -h "$DMG" | cut -f1)), archs: $(lipo -archs "$APP/Contents/MacOS/Glance")"
