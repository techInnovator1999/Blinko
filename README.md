# Blinko

A fast, native Dynamic Island for macOS, written in Swift with SwiftUI and AppKit. It sits on the notch (or draws a virtual one on displays without a notch). It shows live activities (media, HUDs, charging, Bluetooth and AirPods battery, Focus, camera/mic in use, Wi-Fi/VPN, downloads, timers) and opens into a panel with these tabs: home (media with synced lyrics, clock, world clocks, weather, calendar), file shelf, clipboard, system stats, timers, notes and tools (colour picker, Keep Awake).

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
- **Focus Status** (Settings → Live Activities) shows Focus on/off. Optional **Full Disk Access** adds the Focus mode's name.
- **Downloads folder** access is asked for when you turn on download progress.
- **Location** (When In Use, once per session) is asked for when you turn on weather; a city works instead.

Lyrics come from [LRCLIB](https://lrclib.net) and weather from [Open-Meteo](https://open-meteo.com); both are free and need no key.

## Using it

- Hover over the notch, click it, two-finger swipe down on it, or press **⌃⌥Space** to open it. Swipe up or move the pointer away to close it.
- Drag files onto the notch to put them on the shelf. From there you can drag them out again (click several to select them, then drag one to move them all) or AirDrop them.
- The pin in the header keeps the island open. So does typing in Notes; click elsewhere to close it.
- **Settings → Appearance** themes the island with a live preview: an accent colour (presets, custom, or matched to the album art or your wallpaper), a style (Classic, Minimal, Glass, Glow), a size (Compact, Default, Large), corner roundness and SF Pro or SF Pro Rounded numbers. Pick one of the built-in themes (Midnight, Aurora, Paper, Neon), or export yours as a JSON file and import it on another Mac.

## Architecture

```
Sources/Blinko
  App/        entry point, hotkey, status item, launch-at-login, snapshot renderer
  Core/       Preferences, Theme + ThemeLibrary, NotchViewModel (per display), ActivityCenter, Motion/Metrics
  Window/     NotchPanel (non-activating NSPanel), NotchWindowController, NotchManager (multi-display, gestures)
  Services/   NowPlaying, Lyrics, MediaKeys/SystemControls, Battery, Bluetooth, Calendar, Shelf, Clipboard, Stats,
              Timer, Camera, Focus, Privacy, Network, Downloads, Weather, Notes, Tools (colour picker, Keep Awake)
  Views/      NotchShape, root, compact wings, expanded tabs, components, settings
Helper/       BlinkoMedia.m + blinko-media.pl: MediaRemote bridge hosted by Apple's platform perl
Resources/    Info.plist, entitlements, icon, Localizable.xcstrings (String Catalog)
```

**Localisation:** user-facing strings live in `Resources/Localizable.xcstrings`. Run `scripts/extract-strings.sh` after changing UI text to sync the catalog with the code; `build.sh` compiles translations into the app bundle.

**Logo:** `design/logo.swift` draws the mark in code (the island as an eyelid, mid-blink over an iris). Run `scripts/make-icon.sh` to regenerate `AppIcon.icns`.

**Design QA:** `swift build && .build/debug/Blinko --snapshot /tmp/blinko-snaps` renders every state to PNG, plus a theme matrix (styles, size presets × tabs, accents, built-in themes, the Appearance pane). Add `--themes-only` to render just the theme matrix.
