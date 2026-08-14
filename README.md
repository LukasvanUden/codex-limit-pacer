# Codex Limit Pacer

An unofficial macOS menu-bar companion that adds the weekly reset date after **Usage**, plus **Week elapsed** and **Quota used** directly below it in Codex’s account menu.

It reads the signed-in desktop session’s current weekly limit and exact reset time, so there is no Settings visit, copied reset date, or second login. Codex Limit Pacer is independent and not affiliated with OpenAI.

## Install

1. Download the latest `Codex-Limit-Pacer-*.dmg` from [Releases](../../releases/latest).
2. Open it and drag **Codex Limit Pacer** into **Applications**.
3. Start it from Applications. On the first launch, macOS may require Control-click → **Open** because this independent app is not notarized.
4. Finish any active Codex work and approve the one restart if Limit Pacer asks for it.
5. Open Codex’s account menu. The two pace rows appear below **Usage**.

## What it does

- Uses Codex Desktop’s existing signed-in session to read `/wham/usage` once per minute.
- Selects only the base seven-day rate-limit window and calculates elapsed time from its actual reset timestamp.
- Inserts only the two pace rows; it does not add a Settings panel or persist a reset date.
- Never reads or stores an OpenAI token and sends no telemetry to a Limit Pacer service.

## Important caveats

Codex does not offer a supported extension point inside its account menu. To match this placement, the helper restarts Codex once with a loopback-only renderer debugging port and injects a small script into the renderer.

The usage request (`/wham/usage` through Codex’s renderer bridge) is also an undocumented desktop implementation detail. It is read-only and uses the same signed-in session as Codex, but an app update can change it. Use the helper only on a trusted Mac: a local debugging port gives other local processes access to the Codex renderer while Codex is running.

If this stops working after a Codex update, quit Limit Pacer, start Codex normally, then check the project for a compatible release.

## Build from source

Requires macOS 13+ and Apple Command Line Tools:

```sh
xcode-select --install
Scripts/build-app.sh
```

The build produces a universal `build/Codex Limit Pacer.app`. To make the release DMG and ZIP, run:

```sh
CODESIGN_IDENTITY='Apple Distribution: Your Name (TEAMID)' Scripts/build-release.sh
```

Without `CODESIGN_IDENTITY`, the app is ad-hoc signed for local testing. Apple Developer ID signing and notarization are required to remove the first-launch macOS warning for public downloads.

Run the focused checks with:

```sh
node --test Tests/*.mjs
```

## Uninstall

Use the menu-bar icon → **Uninstall Limit Pacer…**, or run `Uninstall Codex Limit Pacer.command`. Codex’s app bundle is never patched.

## License

[MIT](LICENSE)
