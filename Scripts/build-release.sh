#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/Codex Limit Pacer.app"
RELEASE_DIR="$BUILD_DIR/release"
STAGING_DIR="$BUILD_DIR/dmg"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Info.plist")"
NAME="Codex-Limit-Pacer-$VERSION"

"$ROOT/Scripts/build-app.sh"
/bin/rm -rf "$RELEASE_DIR" "$STAGING_DIR"
/bin/mkdir -p "$RELEASE_DIR" "$STAGING_DIR"
/usr/bin/ditto "$APP" "$STAGING_DIR/Codex Limit Pacer.app"
/bin/ln -s /Applications "$STAGING_DIR/Applications"
/usr/bin/hdiutil create -quiet -volname "Codex Limit Pacer" -srcfolder "$STAGING_DIR" -format UDZO -ov "$RELEASE_DIR/$NAME.dmg"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$RELEASE_DIR/$NAME.zip"
/bin/rm -rf "$STAGING_DIR"

printf 'Release files:\n%s\n%s\n' "$RELEASE_DIR/$NAME.dmg" "$RELEASE_DIR/$NAME.zip"
