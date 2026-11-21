#!/bin/sh
# Builds a Developer ID signed Release Glance.app, packages it as dist/Glance-<version>.dmg, notarizes and staples the
# DMG, and adds it to the Sparkle appcast at docs/appcast.xml, signed with the "Glance" EdDSA key in the login keychain.
#
# One-time setup: store App Store Connect credentials for notarytool in the keychain under the "Glance" profile:
#   xcrun notarytool store-credentials Glance --apple-id <apple id> --team-id CR9Y3LFYH4
# (it asks for an app-specific password from account.apple.com). NOTARY_PROFILE overrides the profile name.
#
# Before a release, bump MARKETING_VERSION and CURRENT_PROJECT_VERSION: Sparkle compares the build number.
# Then upload the DMG to the GitHub release tagged v<version> and push docs/ so the landing page serves the appcast.
set -eu

cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

BUILD=build
DIST=dist
APP="$BUILD/Build/Products/Release/Glance.app"
TEAM=CR9Y3LFYH4
IDENTITY="Developer ID Application: Istiaq Ahmmed Nirab ($TEAM)"
NOTARY_PROFILE="${NOTARY_PROFILE:-Glance}"

xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 || {
  echo "No notarytool credentials in the \"$NOTARY_PROFILE\" keychain profile; see the setup note at the top." >&2
  exit 1
}

rm -rf "$APP"
xcodebuild -project Glance.xcodeproj -scheme Glance -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$BUILD" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="$TEAM" \
  ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS="--timestamp" CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO build | grep -E '^(\*\*|error|warning: .*error)' || true

[ -d "$APP" ] || { echo "Build failed: $APP not found" >&2; exit 1; }

# Sparkle's helpers ship ad-hoc signed, and Xcode only re-signs the framework itself, so sign them inside out
# (as Sparkle's docs describe), then the framework and the app.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
sign() { codesign --force --timestamp --options runtime --sign "$IDENTITY" "$@"; }
sign "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
sign "$SPARKLE/Versions/B/Autoupdate"
sign "$SPARKLE/Versions/B/Updater.app"
sign "$SPARKLE"
sign --preserve-metadata=entitlements "$APP"
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

codesign --force --timestamp --sign "$IDENTITY" "$DMG"
echo "Notarizing ${DMG}…"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature -v "$DMG"

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
