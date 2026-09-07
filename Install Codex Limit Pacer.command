#!/bin/bash
set -euo pipefail

clear
printf '\nCodex Limit Pacer 1.0.9 – Source installer\n'
printf '=============================================\n\n'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST_DIR="$HOME/Applications"
DEST_APP="$DEST_DIR/Codex Limit Pacer.app"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This installer only runs on macOS."
  read -r -p "Press Enter to close … "
  exit 1
fi

if ! /usr/bin/xcrun --find swiftc >/dev/null 2>&1; then
  echo "This source installer needs Apple's Command Line Tools."
  echo "Install them with: xcode-select --install"
  read -r -p "Press Enter to close … "
  exit 1
fi

"$SCRIPT_DIR/Scripts/build-app.sh"
/bin/mkdir -p "$DEST_DIR"
/usr/bin/osascript -e 'tell application "Codex Limit Pacer" to quit' >/dev/null 2>&1 || true
sleep 0.5
/bin/rm -rf "$DEST_APP"
/usr/bin/ditto "$SCRIPT_DIR/build/Codex Limit Pacer.app" "$DEST_APP"
/usr/bin/open "$DEST_APP"

cat <<'TEXT'

Installed to ~/Applications/Codex Limit Pacer.app.

Limit Pacer is now in the macOS menu bar. If the rows do not appear, choose
"Restart Codex with menu access…" from the Pacer menu when it is safe. Pacer
does not interrupt an existing Codex session with automatic restart prompts.
TEXT

printf '\n'
read -r -p "Press Enter to close … "
