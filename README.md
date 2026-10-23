# Blinko

A fast, native Dynamic Island for macOS, written in Swift with SwiftUI and AppKit. It sits on the notch (or draws a virtual one on displays without a notch). It shows live activities (media, HUDs, charging, Bluetooth and AirPods battery, Focus, camera/mic in use, Wi-Fi/VPN, downloads, timers) and opens into a panel with these tabs: home (a widget grid you arrange: media with synced lyrics, clock, world clocks, weather, calendar, timers, stats, agents, notes, shelf, clipboard, mirror, battery), file shelf, clipboard, system stats, timers, notes and tools (colour picker, Keep Awake).

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
- **System Audio Recording** (macOS 14.2+) is asked for only when you pick Visualizer → Real (Settings → Appearance). Blinko taps the playing app's audio only while the bars are on screen and music plays, never records it, and falls back to the Classic bars without it.

Meeting mode needs no permission: it sees which app is using the microphone through CoreAudio. Accessibility, if already granted, also lets it read Zoom's mute state and leave Teams, Slack and Zoom calls from the island.

Lyrics come from [LRCLIB](https://lrclib.net), weather from [Open-Meteo](https://open-meteo.com) and exchange rates from [open.er-api.com](https://www.exchangerate-api.com/docs/free); all are free and need no key.

## Using it

- Hover over the notch, click it, two-finger swipe down on it, or press **⌃⌥Space** to open it. Swipe up or move the pointer away to close it.
- Drag files onto the notch to put them on the shelf. From there you can drag them out again (click several to select them, then drag one to move them all) or AirDrop them.
- The pin in the header keeps the island open. So does typing in Notes; click elsewhere to close it.
- **Settings → Home Layout** arranges Home: drag widgets from the palette onto the live island preview, drag them to reorder, switch each between S / M / L, or use the list below the preview (keyboard and VoiceOver friendly). Home holds 10 units (S = 2, M = 3, L = 5). Built-in layouts: **Default** (the classic Home), **Work** (agenda, timers, agents, notes) and **Chill** (big player, weather, clock); editing one saves your version as a new named layout. Right-click the Home tab button in the island to switch layouts. During a call the meeting card takes over the Now Playing widget.
- **Settings → Appearance** themes the island with a live preview: an accent colour (presets, custom, or matched to the album art or your wallpaper), a style (Classic, Minimal, Glass, Glow), a size (Compact, Default, Large), corner roundness and SF Pro or SF Pro Rounded numbers. Pick one of the built-in themes (Midnight, Aurora, Paper, Neon), or export yours as a JSON file and import it on another Mac.
- Press **⌥Space** for the command bar: calculate (`(12+4)*3^2`), convert (`10 km to mi`, `100 usd in eur`), launch apps, run Shortcuts, find clipboard and shelf items, start a timer (`t 25m`) or search the web. ↑↓ choose, ↩ runs, ⎋ closes.
- During a call (Zoom, Teams, Meet, FaceTime, Slack, Discord, Webex) the closed island shows the call's length and your microphone; open it for mute and leave controls.
- The first launch opens a one-minute guided tour (skip it any time); replay it from Settings → About → **Show Tour**.

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
  Core/       Preferences, Theme + ThemeLibrary, HomeLayout, NotchViewModel (per display), ActivityCenter, Motion/Metrics
  Window/     NotchPanel (non-activating NSPanel), NotchWindowController, NotchManager (multi-display, gestures)
  Services/   NowPlaying, Lyrics, MediaKeys/SystemControls, Battery, Bluetooth, Calendar, Shelf, Clipboard, Stats,
              Timer, Camera, Focus, Privacy, Network, Downloads, Weather, Notes, Tools (colour picker, Keep Awake),
              Meeting (+ MutedSpeechDetector), Command bar (parsers, providers),
              AudioSpectrum (process tap capture, FFT/bands DSP, demand-driven service)
  App/        entry point, hotkey, status item, launch-at-login, snapshot renderer, URL scheme + routing, App Intents
  Core/       Preferences, NotchViewModel (per display), ActivityCenter, Motion/Metrics
  Window/     NotchPanel (non-activating NSPanel), NotchWindowController, NotchManager (multi-display, gestures)
  Services/   NowPlaying, Lyrics, MediaKeys/SystemControls, Battery, Bluetooth, Calendar, Shelf, Clipboard, Stats,
              Timer, Camera, Focus, Privacy, Network, Downloads, Weather, Notes, Tools (colour picker, Keep Awake),
              AgentHub (socket server + sessions/approvals)
  Views/      NotchShape, root, compact wings, expanded tabs (+ Expanded/Widgets for Home), components, settings
Sources/BlinkoKit   Agent Hub protocol + Claude Code hook installer (shared by app and CLI)
Sources/BlinkoCLI   the `blinko` command-line tool (Contents/Helpers/blinko)
Helper/       BlinkoMedia.m + blinko-media.pl: MediaRemote bridge hosted by Apple's platform perl
Resources/    Info.plist, entitlements, icon, Localizable.xcstrings (String Catalog)
```

## Localisation

Blinko ships in English, Spanish (`es`), German (`de`), French (`fr`), Japanese (`ja`), Simplified Chinese (`zh-Hans`) and Urdu (`ur`, right-to-left). It follows the macOS language order; try another language without changing yours with `open build/Blinko.app --args -AppleLanguages '(de)'`.

- UI strings live in `Resources/Localizable.xcstrings` (String Catalog, English keys). Permission prompts (Info.plist usage descriptions) live in `Resources/InfoPlist.xcstrings`.
- After changing UI text run `scripts/extract-strings.sh`: it syncs the catalog with the code. New keys show in English until translated.
- `build.sh` compiles both catalogs into `<lang>.lproj/Localizable.strings` and `InfoPlist.strings` in the app bundle.
- Identifiers (SF Symbol names), numbers and product names are marked *Don't translate* (`shouldTranslate: false`).

**Adding a language:** open the two catalogs in Xcode (or edit the JSON) and add the language with a translation for every key, keeping format specifiers (`%@`, `%lld`; use `%1$@`, `%2$@` to reorder) and product names (Blinko, AirDrop, Spotify, Claude Code) as they are. Add the code to `CFBundleLocalizations` in `Resources/Info.plist`, build, and check the snapshots (below) with `--locale xx` for truncation.

**Right-to-left:** layouts use leading/trailing, so Settings, the tour and the island mirror under Urdu like the system does: the wings swap sides around the notch (the leading wing — artwork, app icon — sits on the right), which is how iOS mirrors the Dynamic Island's leading/trailing regions. The notch itself never moves. Media playback (scrubber, previous/play/next) stays left-to-right, as Apple's HIG asks, and so do keyboard shortcuts and the tour's drawings of the physical notch.

## Feedback & crash reports

Nothing leaves your Mac unless you send it. **Send Feedback** (menu bar icon, Settings → About) opens a pre-filled GitHub issue — bug report with version, macOS and Mac model, or feature request — that you review in the browser. At launch Blinko looks for new crash reports macOS wrote for it (`~/Library/Logs/DiagnosticReports/Blinko-*.ips`) and offers once, in a small panel, to open an issue with the exception and the top frames of the crashed thread, with your user name and home folder removed. No SDK, no telemetry. `Blinko --crash-report <file.ips>` prints what would be filled in.

## Landing page

`site/` is a static, dependency-free page (`index.html` + `assets/`). `.github/workflows/pages.yml` deploys it to GitHub Pages on every push to `main` that touches `site/`; enable it once under the repository's Settings → Pages → Source: **GitHub Actions**. Preview locally with `python3 -m http.server -d site`. The island images are real renders: `swift build && .build/debug/Blinko --snapshot /tmp/site-ui --site-only` (transparent PNGs; convert to WebP for the page).

**Logo:** `design/logo.swift` draws the mark in code (the island as an eyelid, mid-blink over an iris). Run `scripts/make-icon.sh` to regenerate `AppIcon.icns`.

**Design QA:** `swift build && .build/debug/Blinko --snapshot /tmp/blinko-snaps` renders every state to PNG, plus a theme matrix (styles, size presets × tabs, accents, built-in themes, the Appearance pane). Add `--themes-only` to render just the theme matrix. `.build/debug/Blinko --selftest` runs the calculator, fuzzy-matcher and parser checks. Lock screen: `--snapshot DIR --lockscreen-only` renders the lock-screen island and widget states (with the privacy-redacted variants); `open -n build/Blinko.app --args --lockscreen-roundtrip-test [report.txt]` moves two test windows into the lock-screen space and back on the unlocked desktop and checks with the window server that they are restored.
**Design QA:** `swift build && .build/debug/Blinko --snapshot /tmp/blinko-snaps` renders every state to PNG, plus a theme matrix (styles, size presets × tabs, accents, built-in themes, the Appearance pane). Add `--themes-only` to render just the theme matrix, or `--home-only` for the Home layouts (built-ins × size presets, dense layouts, meeting takeover, edit mode, the Home Layout pane). `.build/debug/Blinko --selftest` runs the calculator, fuzzy-matcher and parser checks.
**Design QA:** `swift build && .build/debug/Blinko --snapshot /tmp/blinko-snaps` renders every state to PNG, plus a theme matrix (styles, size presets × tabs, accents, built-in themes, the Appearance pane). Add `--themes-only` to render just the theme matrix. `.build/debug/Blinko --selftest` runs the calculator, fuzzy-matcher, parser and visualizer DSP checks.
**Design QA:** `swift build && .build/debug/Blinko --snapshot /tmp/blinko-snaps` renders every state to PNG, plus a theme matrix (styles, size presets × tabs, accents, built-in themes, the Appearance pane), the tour pages, the crash prompt and every Settings pane. Add `--themes-only` for just the theme matrix, `--launch-only` for the tour / crash prompt / Settings. `--locale de` renders everything in one language (right-to-left for `ur`); compile the translations next to the binary first: `xcrun xcstringstool compile Resources/Localizable.xcstrings --output-directory .build/debug && mkdir -p .build/debug/en.lproj`. `.build/debug/Blinko --selftest` runs the calculator, fuzzy-matcher and parser checks.
