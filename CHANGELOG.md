# Changelog

## 1.0.9 — Unreleased

- Removes the automatic Codex restart dialog when menu access is temporarily unavailable.
- Keeps retrying silently and leaves the existing manual restart action in the menu bar.

## 1.0.8 — 2026-09-05

- Restores usage readings on Codex 26.901.41600 by using its desktop HTTP client and fetch service; removes the rejected legacy bridge request.
- Adds Sparkle updates with manual checks and separate opt-in controls for automatic checks and installation; both default to off.
- Signs update feeds and archives with Ed25519; release tooling creates the GitHub-hosted appcast alongside notarized DMG and ZIP downloads.
- Resolves the loaded client without hardcoding asset hashes or minified export names.
- Updates browser tests for the current API client, weekly primary windows, unavailable clients, and browser-local date formatting.
- Publishes universal, Developer ID signed and notarized DMG/ZIP downloads plus the signed appcast as GitHub release `v1.0.8` (build 10).
- Verified with four passing browser tests, live usage in Codex (also confirmed by Lukas), a successful update of a separate app copy from build 9 to 10, rejection of tampered feed/archive signatures, and the public GitHub update feed. Native update-menu interaction still awaits a manual check; the native UI automation service was unavailable.

## 1.0.7 — 2026-08-16

- Automatically takes over a freshly opened Codex when Pacer is already running.
- Falls back to force-quitting Codex when an approved menu-access restart cannot close it normally.
- Marks version 1.0.6 as update-required because of its broken startup and restart flow.
- Ships as a universal macOS app signed with Developer ID and notarized by Apple.

## 1.0.6 — 2026-08-15

- Added continuous renderer monitoring, reconnection, and reinjection.
- Known issue: the startup and restart flow is broken; update to version 1.0.7 or newer.
