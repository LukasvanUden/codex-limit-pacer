# Changelog

## 1.0.8 — 2026-09-05

- Restores usage readings on Codex 26.901.41600 by using its desktop HTTP client and fetch service; removes the rejected legacy bridge request.
- Adds Sparkle updates with manual checks and separate opt-in controls for automatic checks and installation; both default to off.
- Signs update feeds and archives with Ed25519; release tooling creates the GitHub-hosted appcast alongside notarized DMG and ZIP downloads.
- Resolves the loaded client without hardcoding asset hashes or minified export names.
- Updates browser tests for the current API client, weekly primary windows, unavailable clients, and browser-local date formatting.

## 1.0.7 — 2026-08-16

- Automatically takes over a freshly opened Codex when Pacer is already running.
- Falls back to force-quitting Codex when an approved menu-access restart cannot close it normally.
- Marks version 1.0.6 as update-required because of its broken startup and restart flow.
- Ships as a universal macOS app signed with Developer ID and notarized by Apple.

## 1.0.6 — 2026-08-15

- Added continuous renderer monitoring, reconnection, and reinjection.
- Known issue: the startup and restart flow is broken; update to version 1.0.7 or newer.
