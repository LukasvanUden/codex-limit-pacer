#!/bin/bash
set -euo pipefail

APP="$HOME/Applications/Codex Limit Pacer.app"
AGENT="$HOME/Library/LaunchAgents/studio.morje.codexusagepace.plist"
PREFS="$HOME/Library/Preferences/studio.morje.codexusagepace.plist"

clear
printf '\nUninstall Codex Limit Pacer\n=============================\n\n'
read -r -p "Remove Limit Pacer from this Mac? [y/N] " ANSWER
case "$ANSWER" in y|Y|yes|YES) ;; *) echo "Cancelled."; exit 0 ;; esac

/usr/bin/osascript -e 'tell application "Codex Limit Pacer" to quit' >/dev/null 2>&1 || true
sleep 1
/usr/bin/pkill -x CodexLimitPacer 2>/dev/null || true
/bin/launchctl bootout "gui/$(id -u)" "$AGENT" >/dev/null 2>&1 || true
/bin/rm -f "$AGENT" "$PREFS"
/bin/rm -rf "$APP"

cat <<'TEXT'

Codex Limit Pacer was removed.
Codex itself was never modified. If an account menu that was already open still
shows the rows, close and reopen it; the local debug connection also ends on
the next normal Codex restart.
TEXT
read -r -p "Press Enter to close … "
