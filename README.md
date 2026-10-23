# Blinko

A fast, native Dynamic Island for macOS, written in Swift with SwiftUI and AppKit. It sits on the notch (or draws a virtual one on displays without a notch). It shows live activities and opens into a panel with these tabs: media, calendar, file shelf, clipboard, system stats and timer.

The full feature matrix, performance budget and roadmap are in [docs/ROADMAP.md](docs/ROADMAP.md).

## Build & run

Requires macOS 14+ and the Xcode command line tools.

```bash
scripts/build.sh release --run
```

`build/Blinko.app` is code-signed with the first Apple Development identity in your keychain, so permissions survive rebuilds. Override this with `BLINKO_SIGN_IDENTITY`. Open `Package.swift` in Xcode to work on the code.

**Permissions** (requested in context, never at launch):
- **Accessibility** replaces the volume and brightness HUD.
- **Calendar & Reminders** fill the agenda.
- **Camera** powers the mirror.
- **Bluetooth** drives the connect activities.

## Using it

- Hover over the notch, click it, two-finger swipe down on it, or press **⌃⌥Space** to open it. Swipe up or move the pointer away to close it.
- Drag files onto the notch to put them on the shelf. From there you can drag them out again or AirDrop them.
- The pin in the header keeps the island open.

## Architecture

```
Sources/Blinko
  App/        entry point, hotkey, status item, launch-at-login, snapshot renderer
  Core/       Preferences, NotchViewModel (per display), ActivityCenter, Motion/Metrics
  Window/     NotchPanel (non-activating NSPanel), NotchWindowController, NotchManager (multi-display, gestures)
  Services/   NowPlaying, MediaKeys/SystemControls, Battery, Bluetooth, Calendar, Shelf, Clipboard, Stats, Timer, Camera
  Views/      NotchShape, root, compact wings, expanded tabs, components, settings
Helper/       BlinkoMedia.m + blinko-media.pl: MediaRemote bridge hosted by Apple's platform perl
```

**Logo:** `design/logo.swift` draws the mark in code (the island as an eyelid, mid-blink over an iris). Run `scripts/make-icon.sh` to regenerate `AppIcon.icns`.

**Design QA:** `swift build && .build/debug/Blinko --snapshot /tmp/blinko-snaps` renders every state to PNG.
