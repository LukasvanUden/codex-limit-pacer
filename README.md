# Codex Limit Pacer

Keep your weekly Codex limit on pace.

![Codex account menu with the Limit Pacer rows](Assets/Codex-Limit-Pacer.jpg)

Limit Pacer lives right below **Usage** in your Codex account menu.

## Install

1. Download the latest [DMG](../../releases/latest).
2. Drag **Codex Limit Pacer** to **Applications**, then open it.
3. If prompted, let it restart Codex once. Then open your account menu.

It adds the reset date, **Week elapsed**, and **Quota used**. No Settings visit, copied reset date, or extra login.
The universal app is signed with Developer ID and notarized by Apple.

## Notes

- Independent, unofficial, and not affiliated with OpenAI.
- Reads the signed-in desktop session locally once per minute; it never stores tokens or sends telemetry.
- It uses undocumented Codex desktop behavior, so a Codex update may require a Pacer update.
- The one-time restart enables local renderer access while Codex runs; use it on a Mac you trust.

## Build from source

Requires macOS 13+ and Apple Command Line Tools:

```sh
xcode-select --install
Scripts/build-app.sh
```

Or double-click **Install Codex Limit Pacer.command** to build and install it locally.

The project is [MIT licensed](LICENSE).

Built by Lukas van Uden · [X](https://x.com/LukasvanUden) · [LinkedIn](https://www.linkedin.com/in/lukas-van-uden/)
