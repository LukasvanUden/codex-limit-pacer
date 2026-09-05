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
RW_DMG="$BUILD_DIR/$NAME-rw.dmg"
VOLUME_NAME="Codex Limit Pacer"
SPARKLE_DIR="$("$ROOT/Scripts/fetch-sparkle.sh")"
APPCAST_DIR="$BUILD_DIR/appcast"
SPARKLE_ACCOUNT="studio.morje.codexusagepace"

: "${CODESIGN_IDENTITY:?Set CODESIGN_IDENTITY to a Developer ID Application certificate}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to an xcrun notarytool keychain profile}"
if [[ "$CODESIGN_IDENTITY" != Developer\ ID\ Application:* ]]; then
  echo "CODESIGN_IDENTITY must be a Developer ID Application certificate."
  exit 1
fi
PUBLIC_KEY="$("$SPARKLE_DIR/bin/generate_keys" --account "$SPARKLE_ACCOUNT" -p)"
if [[ "$PUBLIC_KEY" != "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$ROOT/Info.plist")" ]]; then
  echo "Sparkle signing key does not match Info.plist." >&2
  exit 1
fi

"$ROOT/Scripts/build-app.sh"
/bin/rm -rf "$RELEASE_DIR" "$STAGING_DIR"
/bin/mkdir -p "$RELEASE_DIR" "$STAGING_DIR"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$NOTARY_ZIP"
/usr/bin/xcrun notarytool submit "$NOTARY_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
/usr/bin/xcrun stapler staple "$APP"
/usr/sbin/spctl -a -vv -t exec "$APP"
/usr/bin/sips -s format png -z 400 680 "$ROOT/Assets/DmgBackground.svg" --out "$STAGING_DIR/background.png" >/dev/null
/usr/bin/hdiutil create -quiet -size 80m -fs HFS+ -volname "$VOLUME_NAME" -ov "$RW_DMG"
MOUNT_POINT="$(/usr/bin/hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG" | /usr/bin/awk -F '\t' 'NF { mount = $NF } END { print mount }')"
/usr/bin/ditto "$APP" "$MOUNT_POINT/Codex Limit Pacer.app"
/bin/ln -s /Applications "$MOUNT_POINT/Applications"
/bin/mkdir "$MOUNT_POINT/.background"
/bin/cp "$STAGING_DIR/background.png" "$MOUNT_POINT/.background/background.png"
/usr/bin/osascript <<APPLESCRIPT
tell application "Finder"
    set mountedDisk to disk of (POSIX file "$MOUNT_POINT" as alias)
    tell mountedDisk
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {100, 100, 780, 500}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 96
        set background picture of theViewOptions to (POSIX file "$MOUNT_POINT/.background/background.png" as alias)
        set position of item "Codex Limit Pacer.app" to {180, 220}
        set position of item "Applications" to {500, 220}
        close
        open
        update without registering applications
    end tell
end tell
APPLESCRIPT
/usr/bin/hdiutil detach "$MOUNT_POINT" >/dev/null
/usr/bin/hdiutil convert -quiet "$RW_DMG" -format UDZO -o "$RELEASE_DIR/$NAME.dmg"
/usr/bin/codesign --force --sign "$CODESIGN_IDENTITY" --timestamp "$RELEASE_DIR/$NAME.dmg"
/usr/bin/xcrun notarytool submit "$RELEASE_DIR/$NAME.dmg" --keychain-profile "$NOTARY_PROFILE" --wait
/usr/bin/xcrun stapler staple "$RELEASE_DIR/$NAME.dmg"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$RELEASE_DIR/$NAME.zip"
/bin/rm -rf "$APPCAST_DIR"
/bin/mkdir -p "$APPCAST_DIR"
/bin/cp "$RELEASE_DIR/$NAME.dmg" "$APPCAST_DIR/"
"$SPARKLE_DIR/bin/generate_appcast" --account "$SPARKLE_ACCOUNT" \
  --maximum-deltas 0 \
  --download-url-prefix "https://github.com/LukasvanUden/codex-limit-pacer/releases/download/v$VERSION/" \
  --link "https://github.com/LukasvanUden/codex-limit-pacer/releases/tag/v$VERSION" \
  "$APPCAST_DIR"
/bin/cp "$APPCAST_DIR/appcast.xml" "$RELEASE_DIR/appcast.xml"
"$SPARKLE_DIR/bin/sign_update" --account "$SPARKLE_ACCOUNT" --verify "$RELEASE_DIR/appcast.xml"
/bin/rm -rf "$STAGING_DIR" "$NOTARY_ZIP" "$RW_DMG"

printf 'Release files:\n%s\n%s\n%s\n' "$RELEASE_DIR/$NAME.dmg" "$RELEASE_DIR/$NAME.zip" "$RELEASE_DIR/appcast.xml"
