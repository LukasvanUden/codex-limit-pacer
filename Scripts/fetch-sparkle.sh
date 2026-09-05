#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="2.9.6"
SHA256="52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192"
DEPS="$ROOT/build/dependencies"
ARCHIVE="$DEPS/Sparkle-$VERSION.tar.xz"
DEST="$DEPS/Sparkle-$VERSION"

/bin/mkdir -p "$DEPS"
if [[ ! -f "$ARCHIVE" ]]; then
  /usr/bin/curl --fail --location --retry 2 \
    "https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/Sparkle-$VERSION.tar.xz" \
    -o "$ARCHIVE.download"
  /bin/mv "$ARCHIVE.download" "$ARCHIVE"
fi
if [[ "$(/usr/bin/shasum -a 256 "$ARCHIVE" | /usr/bin/awk '{print $1}')" != "$SHA256" ]]; then
  echo "Sparkle archive checksum mismatch." >&2
  exit 1
fi
/bin/mkdir -p "$DEST"
/usr/bin/tar -xf "$ARCHIVE" -C "$DEST"
printf '%s\n' "$DEST"
