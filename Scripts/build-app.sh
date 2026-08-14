#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/Codex Limit Pacer.app"
MODULE_CACHE="$BUILD_DIR/module-cache"
ARCHS=(arm64 x86_64)

if ! /usr/bin/xcrun --find swiftc >/dev/null 2>&1; then
  echo "Apple Command Line Tools are required. Run: xcode-select --install"
  exit 1
fi

/bin/rm -rf "$APP"
/bin/rm -rf "$MODULE_CACHE"
/bin/mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$MODULE_CACHE"
/bin/cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
/bin/cp "$ROOT/Resources/injector.js" "$APP/Contents/Resources/injector.js"

SDK_PATH="$(/usr/bin/xcrun --show-sdk-path)"
for ARCH in "${ARCHS[@]}"; do
  /usr/bin/xcrun swiftc \
    -swift-version 5 \
    -O \
    -target "$ARCH-apple-macos13.0" \
    -sdk "$SDK_PATH" \
    -module-cache-path "$MODULE_CACHE/$ARCH" \
    -framework AppKit \
    -framework Foundation \
    "$ROOT"/Source/*.swift \
    -o "$MODULE_CACHE/CodexLimitPacer-$ARCH"
done
/usr/bin/lipo -create "$MODULE_CACHE"/CodexLimitPacer-* -output "$APP/Contents/MacOS/CodexLimitPacer"
/bin/rm -rf "$MODULE_CACHE"

/bin/chmod 755 "$APP/Contents/MacOS/CodexLimitPacer"
/usr/bin/iconutil -c icns "$ROOT/Assets/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
/usr/bin/plutil -lint "$APP/Contents/Info.plist" >/dev/null
/usr/bin/codesign --force --deep --sign "${CODESIGN_IDENTITY:--}" --timestamp=none "$APP"
/usr/bin/codesign --verify --deep --strict "$APP"

printf 'Built:\n%s\n' "$APP"
