# Bettercast

A tiny, fully native macOS launcher — the essentials, without the bloat.

<p align="center">
  <a href="https://discord.gg/v2Eeb4QQy3">
    <img alt="Join the Bettercast Discord"
         src="https://img.shields.io/badge/Discord-Join%20the%20community-5865F2?style=flat&logo=discord&logoColor=white"></a>
  <a href="mailto:iabueammar@gmail.com?subject=Hiring%20enquiry">
    <img alt="Hire me — iabueammar@gmail.com"
         src="https://img.shields.io/badge/Hire%20me-Let's%20talk-111111?style=flat&logo=gmail&logoColor=white"></a>
  <a href="LICENSE">
    <img alt="License: AGPL-3.0"
         src="https://img.shields.io/badge/License-AGPL--3.0-3DA639?style=flat"></a>
</p>

<!-- Screenshot placeholder — drop the real image at docs/screenshot.png -->
<p align="center">
  <img src="docs/screenshot.png" alt="Bettercast command palette" width="720">
</p>

Around **3 MB on disk** and **under 100 MB of RAM** — no Electron, no telemetry, no background
CPU churn. Just SwiftUI + AppKit with zero dependencies. It's fast because there's nothing to it.

## Features

- **App launcher** — fuzzy-search and launch anything, pin favorites, see what's running, quit an app
  or every app at once.
- **Calculator** — do math, unit and live currency conversions inline, right in the palette.
- **Clipboard history** — text and images, searchable, pasted back into the app you were using.
- **Global hotkey** — one shortcut summons the palette from anywhere.
- **Per-app hotkeys** — bind a key to an app; press it to toggle (focus/hide).

## Install

Bettercast is not distributed yet. Build it from source with Xcode 26:

```sh
xcodegen generate
xcodebuild -project Bettercast.xcodeproj -scheme Bettercast -configuration Debug \
  CODE_SIGNING_ALLOWED=NO build
```

The project started from an upstream AGPL-3.0 project; its license and
attribution remain in this repository.

## Permissions

**Accessibility** — needed only so Bettercast can paste a clipboard item back into the app you
came from. You're prompted the first time you paste; grant it in **System Settings → Privacy &
Security → Accessibility**.

## Using it

1. Open **Settings → General** and record a global shortcut to summon Bettercast.
2. Press it anywhere → the palette floats in. Type to filter, **↵** to launch.
3. **Tab** switches between Apps and Clipboard; **↑/↓** move, **Esc** dismisses.
4. **Settings → App Hotkeys** — search an app and record a shortcut to toggle it.

## Building from source

See **[docs/development.md](docs/development.md)** for the toolchain, build, and test workflow, and
**[docs/ui.md](docs/ui.md)** for the UI design system.

## Contributing

Read **[CONTRIBUTING.md](CONTRIBUTING.md)** first — it covers the memory budget every PR is held to,
the before/after video requirement for visual changes, and why features get declined. Security issues
go through [SECURITY.md](SECURITY.md), not the issue tracker.

Questions, ideas, or just want to follow along? **[Join the Discord](https://discord.gg/v2Eeb4QQy3)**.

## Contributors

Bettercast builds on the work of the [upstream contributors](https://github.com/abue-ammar/tinycast/graphs/contributors).

## License

[AGPL-3.0](LICENSE)
