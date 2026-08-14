#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/Codex Limit Pacer.app"
RELEASE_DIR="$BUILD_DIR/release"
STAGING_DIR="$BUILD_DIR/dmg"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Info.plist")"
NAME="Codex-Limit-Pacer-$VERSION"
NOTARY_ZIP="$BUILD_DIR/$NAME-notary.zip"

: "${CODESIGN_IDENTITY:?Set CODESIGN_IDENTITY to a Developer ID Application certificate}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to an xcrun notarytool keychain profile}"
if [[ "$CODESIGN_IDENTITY" != Developer\ ID\ Application:* ]]; then
  echo "CODESIGN_IDENTITY must be a Developer ID Application certificate."
  exit 1
fi

"$ROOT/Scripts/build-app.sh"
/bin/rm -rf "$RELEASE_DIR" "$STAGING_DIR"
/bin/mkdir -p "$RELEASE_DIR" "$STAGING_DIR"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$NOTARY_ZIP"
/usr/bin/xcrun notarytool submit "$NOTARY_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
/usr/bin/xcrun stapler staple "$APP"
/usr/sbin/spctl -a -vv -t exec "$APP"
/usr/bin/ditto "$APP" "$STAGING_DIR/Codex Limit Pacer.app"
/bin/ln -s /Applications "$STAGING_DIR/Applications"
/usr/bin/hdiutil create -quiet -volname "Codex Limit Pacer" -srcfolder "$STAGING_DIR" -format UDZO -ov "$RELEASE_DIR/$NAME.dmg"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$RELEASE_DIR/$NAME.zip"
/bin/rm -rf "$STAGING_DIR" "$NOTARY_ZIP"

printf 'Release files:\n%s\n%s\n' "$RELEASE_DIR/$NAME.dmg" "$RELEASE_DIR/$NAME.zip"
