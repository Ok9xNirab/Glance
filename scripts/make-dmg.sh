#!/bin/sh
# Builds an ad-hoc signed Release Glance.app, packages it as dist/Glance-<version>.dmg, and adds it to the Sparkle
# appcast at docs/appcast.xml, signed with the "Glance" EdDSA key in the login keychain.
# Before a release, bump MARKETING_VERSION and CURRENT_PROJECT_VERSION: Sparkle compares the build number.
# Then upload the DMG to the GitHub release tagged v<version> and push docs/ so the landing page serves the appcast.
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
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist")
APPCAST=docs/appcast.xml
if [ -f "$APPCAST" ] && grep -q "<sparkle:version>$BUILD_NUMBER</sparkle:version>" "$APPCAST"; then
  echo "Build $BUILD_NUMBER is already in $APPCAST; bump CURRENT_PROJECT_VERSION." >&2
  exit 1
fi
DMG="$DIST/Glance-$VERSION.dmg"

rm -rf "$DIST/dmg" "$DMG"
mkdir -p "$DIST/dmg"
cp -R "$APP" "$DIST/dmg/"
ln -s /Applications "$DIST/dmg/Applications"
hdiutil create -volname "Glance" -srcfolder "$DIST/dmg" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$DIST/dmg"

# generate_appcast keeps the items already in the appcast and adds the one archive in the staging folder.
GENERATE_APPCAST="$BUILD/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast"
STAGING="$DIST/appcast"
rm -rf "$STAGING" && mkdir -p "$STAGING"
cp "$DMG" "$STAGING/"
"$GENERATE_APPCAST" --account Glance \
  --download-url-prefix "https://github.com/Ok9xNirab/Glance/releases/download/v$VERSION/" \
  --link "https://glance.nirab.me" -o "$APPCAST" "$STAGING"
rm -rf "$STAGING"

echo "Created $DMG ($(du -h "$DMG" | cut -f1)), archs: $(lipo -archs "$APP/Contents/MacOS/Glance")"
echo "Updated $APPCAST; upload $DMG to the v$VERSION release, then push docs/."
