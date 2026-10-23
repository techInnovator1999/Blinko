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
- **Microphone** is asked for only when you turn on the "You're muted" warning (Settings → Meetings). Blinko listens only while you are muted in a call and never records.

Meeting mode needs no permission: it sees which app is using the microphone through CoreAudio. Accessibility, if already granted, also lets it read Zoom's mute state and leave Teams, Slack and Zoom calls from the island.

Lyrics come from [LRCLIB](https://lrclib.net), weather from [Open-Meteo](https://open-meteo.com) and exchange rates from [open.er-api.com](https://www.exchangerate-api.com/docs/free); all are free and need no key.

## Using it

- Hover over the notch, click it, two-finger swipe down on it, or press **⌃⌥Space** to open it. Swipe up or move the pointer away to close it.
- Drag files onto the notch to put them on the shelf. From there you can drag them out again (click several to select them, then drag one to move them all) or AirDrop them.
- The pin in the header keeps the island open. So does typing in Notes; click elsewhere to close it.
- **Settings → Appearance** themes the island with a live preview: an accent colour (presets, custom, or matched to the album art or your wallpaper), a style (Classic, Minimal, Glass, Glow), a size (Compact, Default, Large), corner roundness and SF Pro or SF Pro Rounded numbers. Pick one of the built-in themes (Midnight, Aurora, Paper, Neon), or export yours as a JSON file and import it on another Mac.
- Press **⌥Space** for the command bar: calculate (`(12+4)*3^2`), convert (`10 km to mi`, `100 usd in eur`), launch apps, run Shortcuts, find clipboard and shelf items, start a timer (`t 25m`) or search the web. ↑↓ choose, ↩ runs, ⎋ closes.
- During a call (Zoom, Teams, Meet, FaceTime, Slack, Discord, Webex) the closed island shows the call's length and your microphone; open it for mute and leave controls.

### AI coding agents (Agent Hub)

Settings → Agents → **Connect Claude Code** adds Blinko's hooks to `~/.claude/settings.json`. Your other hooks and settings are kept, and the previous file is saved as `settings.json.blinko-backup`. Restart any running Claude Code sessions afterwards. The closed island then shows a spinner, the project and the running tool while Claude works. The **Agents** tab lists every session.

When Claude asks for permission, the island opens on an approval card. Click **Approve** or **Deny**, or click the card and press ⌘↩ / esc. **Answer in Terminal** hands the question back to Claude Code. If you don't answer in time (90 s by default), or Blinko isn't running, Claude Code asks in the terminal as usual. **Disconnect** removes only Blinko's entries.

Other agents (Codex, Cursor, scripts) can report over the same local socket: see [docs/AGENT_PROTOCOL.md](docs/AGENT_PROTOCOL.md).

### Automation: URL scheme, CLI, Shortcuts

```bash
open 'blinko://alert?title=Build%20passed&body=42%20s&icon=checkmark.seal.fill&color=green&duration=4'
open 'blinko://timer?minutes=25&label=Deep%20work'
open 'blinko://open?tab=shelf'          # home, shelf, clipboard, stats, timer, notes, tools, agents
open 'blinko://focus/start'             # focus/stop
open 'blinko://shelf/add?path=/Users/me/Desktop/report.pdf'
open 'blinko://keepawake?minutes=60'    # no minutes = until stopped, off=1 stops
```

Settings → Automation → **Install Command-Line Tool** links `blinko` into `/usr/local/bin` if it is writable, otherwise into `~/.local/bin`. No administrator password is used. The commands mirror the URL scheme:

```bash
blinko alert "Deploy done" --body "api · 2 min" --icon checkmark.circle.fill --color "#34C759"
blinko timer 5 --label Tea
blinko focus            # blinko focus stop
blinko open shelf
blinko shelf add *.pdf
blinko keepawake 30     # on | off
blinko claude install   # same as Connect Claude Code (--settings PATH for another file)
```

In **Shortcuts**, Blinko's own actions appear under Blinko: Show Alert, Start Timer, Start Focus Session, Open Island, Add to Shelf, Keep Mac Awake. "Open URLs" with a `blinko://` link and "Run Shell Script" with the `blinko` tool work as well.

### Lock screen (experimental)

**Settings → Lock Screen** (off by default) shows Blinko on the lock screen: the island at the notch with music, charging and timer / Pomodoro activities, and an optional row of widgets below the middle of the main display (now playing with artwork and previous / play / next, battery, next calendar event, active timer). On the lock screen the island never opens on hover; a tap opens only the music player. Calendar titles are hidden unless you turn on "Show calendar details on lock screen", and the clipboard, shelf, notes, downloads, meetings, custom alerts and (by default) AI agents never appear there.

It uses a private macOS window-server API (a SkyLight space above the lock screen, as boring.notch and other notch apps do), resolved at runtime: if a macOS update removes it, the setting is greyed out. While your Mac is unlocked it only listens for the lock notification.

## Architecture

```
Sources/Blinko
  App/        entry point, hotkey, status item, launch-at-login, snapshot renderer
  Core/       Preferences, Theme + ThemeLibrary, NotchViewModel (per display), ActivityCenter, Motion/Metrics
  Window/     NotchPanel (non-activating NSPanel), NotchWindowController, NotchManager (multi-display, gestures)
  Services/   NowPlaying, Lyrics, MediaKeys/SystemControls, Battery, Bluetooth, Calendar, Shelf, Clipboard, Stats,
              Timer, Camera, Focus, Privacy, Network, Downloads, Weather, Notes, Tools (colour picker, Keep Awake),
              Meeting (+ MutedSpeechDetector), Command bar (parsers, providers)
  App/        entry point, hotkey, status item, launch-at-login, snapshot renderer, URL scheme + routing, App Intents
  Core/       Preferences, NotchViewModel (per display), ActivityCenter, Motion/Metrics
  Window/     NotchPanel (non-activating NSPanel), NotchWindowController, NotchManager (multi-display, gestures)
  Services/   NowPlaying, Lyrics, MediaKeys/SystemControls, Battery, Bluetooth, Calendar, Shelf, Clipboard, Stats,
              Timer, Camera, Focus, Privacy, Network, Downloads, Weather, Notes, Tools (colour picker, Keep Awake),
              AgentHub (socket server + sessions/approvals)
  Views/      NotchShape, root, compact wings, expanded tabs, components, settings
Sources/BlinkoKit   Agent Hub protocol + Claude Code hook installer (shared by app and CLI)
Sources/BlinkoCLI   the `blinko` command-line tool (Contents/Helpers/blinko)
Helper/       BlinkoMedia.m + blinko-media.pl: MediaRemote bridge hosted by Apple's platform perl
Resources/    Info.plist, entitlements, icon, Localizable.xcstrings (String Catalog)
```

**Localisation:** user-facing strings live in `Resources/Localizable.xcstrings`. Run `scripts/extract-strings.sh` after changing UI text to sync the catalog with the code; `build.sh` compiles translations into the app bundle.

**Logo:** `design/logo.swift` draws the mark in code (the island as an eyelid, mid-blink over an iris). Run `scripts/make-icon.sh` to regenerate `AppIcon.icns`.

**Design QA:** `swift build && .build/debug/Blinko --snapshot /tmp/blinko-snaps` renders every state to PNG, plus a theme matrix (styles, size presets × tabs, accents, built-in themes, the Appearance pane). Add `--themes-only` to render just the theme matrix. `.build/debug/Blinko --selftest` runs the calculator, fuzzy-matcher and parser checks. Lock screen: `--snapshot DIR --lockscreen-only` renders the lock-screen island and widget states (with the privacy-redacted variants); `open -n build/Blinko.app --args --lockscreen-roundtrip-test [report.txt]` moves two test windows into the lock-screen space and back on the unlocked desktop and checks with the window server that they are restored.
