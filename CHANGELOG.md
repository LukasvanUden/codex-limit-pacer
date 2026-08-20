# Changelog

## 1.0.7 — 2026-08-16

- Automatically takes over a freshly opened Codex when Pacer is already running.
- Falls back to force-quitting Codex when an approved menu-access restart cannot close it normally.
- Marks version 1.0.6 as update-required because of its broken startup and restart flow.
- Ships as a universal macOS app signed with Developer ID and notarized by Apple.

## 1.0.6 — 2026-08-15

- Added continuous renderer monitoring, reconnection, and reinjection.
- Known issue: the startup and restart flow is broken; update to version 1.0.7 or newer.
