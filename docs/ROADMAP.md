# Blinko — Feature Matrix & Roadmap

Research basis (Oct 2026): boring.notch, Atoll, MewNotch, NotchDrop, DynamicNotchKit, jackson-storm/DynamicNotch,
Cyclop, SuperIsland, ComfyNotch, vibe-notch / notchi (agent status), plus closed-source NotchNook and Alcove.

Legend: ✅ shipped in v0.1 · ✅ v0.x shipped in that version · 🟡 partial / best-effort · ⏭ planned

## 1. Feature matrix

### Media
| Feature | Status | Notes |
|---|---|---|
| Now Playing for any source (Music, Spotify, browsers, video) | ✅ | Own MediaRemote bridge in `/usr/bin/perl` (macOS 15.4+ restriction) |
| Fallback when bridge unavailable | ✅ | Music/Spotify distributed notifications + AppleScript |
| Artwork, title, artist, source-app badge | ✅ | Artwork decoded once per track, downsampled to 256 px |
| Seekable scrubber, prev / play-pause / next | ✅ | Position extrapolated from anchor time; ticks only while visible |
| Album-tinted accent colour + ambient glow | ✅ | 1×1 average, saturation-clamped |
| Compact live activity (artwork + visualizer) | ✅ | Visualizer is pure Core Animation (zero per-frame app CPU) |
| Track-change peek | ✅ | |
| Shuffle / repeat, ±10 s seek, horizontal swipe for tracks | ✅ v0.2 | AppleScript for Music/Spotify (exact state), MRCommand 6/7 elsewhere; ±10 s on artwork hover |
| Synced lyrics (LRCLIB) | ✅ v0.3 | Fetched only by views that show lyrics (`.task(id: track)`): on track change while the player or the compact wing is visible. Exact `/api/get` match, then closest synced `/api/search` result. NSCache + pruned disk cache in Application Support (misses cached too). Redraws via a `TimelineSchedule` that fires at line boundaries only. Optional current line in a wider closed-island wing (default off) |
| Real FFT spectrum (ScreenCaptureKit audio tap) | ⏭ v0.4 | Opt-in, costs a permission |
| AirPlay / output device picker, per-app volume | ⏭ v0.4 | |

### HUD replacement
| Feature | Status | Notes |
|---|---|---|
| Volume / mute HUD, system OSD suppressed | ✅ | CGEventTap (self-healing on timeout), CoreAudio listeners without leaks |
| Display brightness HUD | ✅ | DisplayServices (built-in display) |
| Keyboard backlight HUD | ✅ | CoreBrightness `KeyboardBrightnessClient` |
| Fine steps (⌥⇧), ⌥ opens Settings pane | ✅ | |
| Changes from Control Center / AirPods reflected | ✅ | CoreAudio property listener |
| Caps Lock, mic input volume HUD | ✅ v0.2 | Caps Lock via the existing event tap (observe-only); mic via CoreAudio input listener |
| External display brightness (DDC) | ⏭ v0.4 | |

### Power & connectivity
| Feature | Status | Notes |
|---|---|---|
| Plug / unplug / charging activity | ✅ | IOPS run-loop notification, zero polling |
| Low battery alerts (20/10/5 %) | ✅ | |
| Battery in header + time remaining + Low Power | ✅ | |
| Bluetooth connect / disconnect activity | ✅ | IOBluetooth notifications, device-type icons |
| AirPods battery levels | 🟡 v0.3 | **Best-effort.** Private `IOBluetoothDevice` KVC keys (`batteryPercentLeft/Right/Case/Single`), each guarded by `responds(to:)`; read at connect and once more 1.5 s later. L / R / case shown in a wider Bluetooth wing. Not every model/macOS reports them |
| Wi-Fi / VPN / Hotspot alerts | ✅ v0.3 | `NWPathMonitor` on its own queue, debounced 1.2 s. VPN = a `utun`/`ipsec`/`ppp`/`wg` interface in the path; Hotspot = Wi-Fi + `isExpensive`. SSID via CoreWLAN only if Location is already authorized (never requested for this) |
| Downloads progress live activity | ✅ v0.3 | Opt-in (macOS asks for Downloads access). `DispatchSource` on ~/Downloads; sizes sampled at 2 Hz only while a `.download` (Safari, total from its Info.plist) / `.crdownload` / `.part` exists. Progress ring (render-server spinner when the size is unknown), "Downloaded" activity: click adds it to the shelf; the shelf also offers it for 5 min |

### Productivity
| Feature | Status | Notes |
|---|---|---|
| Calendar agenda + reminders | ✅ | EventKit change notifications only |
| One-click meeting join (Zoom/Meet/Teams/Webex/FaceTime) | ✅ | |
| File shelf (drop on notch, drag out, persisted) | ✅ | QuickLook thumbnails off-main, bounded NSCache |
| AirDrop from shelf / drop-to-AirDrop | ✅ | |
| Clipboard history (text/images/files) | ✅ | Skips password-manager concealed items, memory-only |
| Timer with presets, pause, +1 min, compact countdown | ✅ | Date-based: no ticking model timer |
| System stats: CPU / memory / network / battery | ✅ | Samples only while the tab is visible |
| Camera mirror | ✅ | Session lazy, runs only while visible, `.medium` preset |
| Pomodoro (focus / short / long break, auto-advance) | ✅ v0.2 | Configurable lengths |
| Multiple concurrent timers | ✅ v0.3 | Up to 6 countdowns beside the single Pomodoro session; one completion work item each. Per-timer pause / resume / cancel (+1 min in the context menu); closed island shows the soonest with a "+N" badge |
| Clock: Home widget, header time, idle clock in closed island | ✅ v0.2 | `TimelineView(.everyMinute)`, only while visible |
| World clocks | ✅ v0.3 | Up to 3 zones (searchable picker in Settings) under the Home clock, with day offset |
| Notes / snippets | ✅ v0.3 | New **Notes** tab: scratchpad with debounced autosave to Application Support, snippets (click to copy). Text fields make the non-activating panel key; the island stays open while it is key and closes when you click elsewhere |
| Colour picker, Keep Awake (caffeinate) | ✅ v0.3 | New **Tools** tab: `NSColorSampler`, HEX / RGB / HSL click-to-copy, last 8 colours. Keep Awake = `IOPMAssertion` (PreventUserIdleDisplaySleep) for 15 min / 1 h / ∞, released on stop and quit; cup in the header while on |
| Weather | ✅ v0.3 | Open-Meteo, no key. Off by default. One-shot CoreLocation fix (When In Use, asked when you enable weather) or a city searched via Open-Meteo geocoding. 30 min timer (5 min tolerance) + catch-up on wake, cached result, decoding off main. Chip beside the Home clock flips the agenda column to a 5-hour forecast; temperature in the header elsewhere |
| Shelf expiry, multi-select drag-out | ✅ v0.3 | Expiry Off / 1 day / 1 week, purged at launch and when the shelf is shown (no timers). Dragging a selected tile drags the whole selection (AppKit dragging session, one item per file) |
| LocalSend | ⏭ | Postponed |
| Meeting mode | ✅ v0.4 | **No permission.** CoreAudio per-process objects (`kAudioHardwarePropertyProcessObjectList`, `kAudioProcessPropertyIsRunningInput/Output`, `BundleID`) say which app captures the mic: Zoom, Teams, Webex, FaceTime (via `avconferenced`), Slack huddles, Discord, browsers (Meet & co., helper processes mapped to their browser). Listeners on the process list + meeting-app processes + NSWorkspace launch/terminate/activate; fallback "mic in use + meeting app running" if the API is missing. Compact wing: app icon, mic state, call length (`Text(timerInterval:)`). Home swaps the player for a meeting card: Mute (system input `kAudioDevicePropertyMute`), camera indicator, Show, Leave, title from the calendar event happening now. Leave posts the app's own shortcut (Teams/Slack ⌘⇧H, Zoom ⌘W + confirm) only if Accessibility is already granted, else brings the call to front. No window titles (would need Screen Recording) |
| "You're muted" warning | 🟡 v0.4 | **Best-effort, opt-in (Microphone).** A hardware/system mute silences the input for *every* process (Apple's header: voice detection "works when a process mute is used, but not with hardware mute"), so Blinko's own Mute can't be paired with speech detection. The warning covers mutes made *inside the meeting app*: Zoom (its "Mute/Unmute Audio" menu item read via Accessibility every 2 s, only during a Zoom call, English titles) and native apps that release the mic while call audio keeps playing. Then an `AVAudioEngine` input tap runs with CoreAudio voice activity detection (echo-cancelled, event-driven) or an RMS fallback; 0.6 s of voice shows "You're muted" + Unmute (app's own mute shortcut with Accessibility, else bring to front). apps that keep the mic open while muted and expose no mute state (not verified per app; possibly Teams, Meet, Slack) get no warning. Untested against live calls |
| Command bar (⌥Space) | ✅ v0.4 | Second Carbon hotkey (configurable, conflict-checked). Island grows to 280 pt only while it is up; panel becomes key like Notes; ↑↓ ↩ ⌘↩ ⎋, click outside closes and focus returns to the previous app. Providers: safe recursive-descent calculator (+ − × ÷ ^ % !, functions, constants, bounded depth, typed errors — no NSExpression), units (`Measurement`), currency (open.er-api.com, fetched only when a currency is typed, cached a day), clipboard, shelf, apps (indexed lazily off main), Apple Shortcuts (`shortcuts list/run`), Blinko actions (`t 5m`, focus, `awake 2h`, open tab, mute mic), web search / URL. Fuzzy ranking (prefix > word prefix > acronym > subsequence ≥ 3 letters), ≤ 6 rows. `Blinko --selftest` covers parser, matcher, durations, units, currency parsing and the speech meter |

### System status
| Feature | Status | Notes |
|---|---|---|
| Focus / DND indicator | 🟡 v0.3 | **Two sources.** With Full Disk Access: `~/Library/DoNotDisturb/DB` watched by a `DispatchSource` (fully event-driven, shows the mode's name and icon). Otherwise `INFocusStatusCenter` (authorize in Settings → Live Activities): on/off only; it has no change notification for regular apps, so it is re-read on app switches / wake plus one 20 s timer (10 s tolerance) that exists only while authorized and enabled. Scheduled Focus modes may be reported late on the second path |
| Camera / microphone in use | ✅ v0.3 | CoreMediaIO + CoreAudio `DeviceIsRunningSomewhere` listeners (default input re-attached on change, old listeners removed). Green / orange dots at the wing edge (or a small privacy wing when nothing else shows) + a transient activity on start. Blinko's own mirror is ignored |
| Screen-recording indicator | ⏭ | **Skipped:** no public, reliable "screen is being captured" signal (ScreenCaptureKit only reports your own streams). Revisit if macOS adds one |
| App notifications in the island | ⏭ v0.5 (no public API; research) | |
| AI coding-agent status + approvals (Claude Code hooks → socket) | ⏭ v0.4 | |

### Display, interaction, app
| Feature | Status | Notes |
|---|---|---|
| Exact notch geometry, virtual island on non-notch displays | ✅ | `safeAreaInsets` + `auxiliaryTop*Area` |
| Built-in / main / all displays, hot-plug | ✅ | Keyed by `CGDirectDisplayID` |
| Hide in fullscreen spaces | ✅ | Checked only on space/app switch |
| Hover to open (configurable delay), click to open | ✅ | |
| Two-finger swipe down / up | ✅ | |
| Hover "peek", haptics, pin open | ✅ | |
| Global shortcut ⌃⌥Space | ✅ | Carbon hotkey, no permission |
| Spring motion system, blur-reveal transitions | ✅ | `Motion.swift` |
| Reduced motion | ✅ v0.3 | Follows `accessibilityDisplayShouldReduceMotion` (change notification) or the Appearance override: springs become short fades, the island reveal drops blur/scale |
| Settings window, onboarding, menu bar icon, launch at login | ✅ | |
| Snapshot renderer (`--snapshot <dir>`) for design QA | ✅ | v0.3 adds every new activity, tab and the busiest header; v0.4 adds a theme matrix (styles × states, sizes × tabs, accents, themes, corners, the Appearance pane); `--themes-only` renders just that |
| Customisable shortcut, reorderable / hideable tabs, island size tuning | ✅ v0.2 | Settings → General / Layout; new tabs are appended automatically |
| Lock-screen widgets (SkyLight space) | ⏭ v0.5 | Private API |
| Signed + notarized DMG (`scripts/release.sh`) | ✅ v0.2 | Needs a Developer ID cert + notary profile |
| Sparkle auto-updates | ✅ v0.2 | Appcast on GitHub Releases |
| Localisation | 🟡 v0.3 | **Infrastructure, English only.** `Resources/Localizable.xcstrings` (≈240 keys) generated from the code by `scripts/extract-strings.sh` (compiler `-emit-localized-strings` + `xcstringstool sync`, i.e. what Xcode does). `build.sh` compiles it into `<lang>.lproj` in the main bundle, so plain `Text("…")` / `String(localized:)` pick translations up without a SwiftPM resource bundle. Add a language by translating the catalog in Xcode |
| Extensions / plugins (JavaScriptCore) | ⏭ v0.6 | |

### Themes & island styles (v0.4)
| Feature | Status | Notes |
|---|---|---|
| App-wide accent colour | ✅ v0.4 | `Theme` (`Core/Theme.swift`), derived from Preferences and read at leaf views. Presets Blinko Pink / Violet / Ocean / Mint / Sunset / Mono, custom (system colour panel), Match album art, Match wallpaper. Used for the selected tab and Timer/Focus pills, volume / backlight / mic bars, scrubber + visualizer when album tint is off, countdown ring and rows, preset chips, shelf selection, pin, Notes focus ring. Semantic colours (battery, camera, mic, Pomodoro, Keep Awake, brightness) unchanged |
| Match wallpaper | ✅ v0.4 | `NSWorkspace.desktopImageURL(for:)` read through an ImageIO thumbnail off-main, hue histogram → lifted dominant colour. Observes `activeSpaceDidChange` / screen-parameter changes **only while that preset is selected**; no timers. Folders / dynamic aerials that ImageIO can't read fall back to Blinko Pink |
| Island styles | ✅ v0.4 | Classic; Minimal (header and credit hidden until the pointer is over them, 5 % smaller type, tighter radii — opacity only, layout and window never change with hover); Glass (frosted wash + inner rim light, top third kept pure black); Glow (accent halo under the open island, window padding 28 → 40 pt). The closed island always stays plain black |
| Size presets | ✅ v0.4 | Compact 640 / Default 700 / Large 780 pt. A preset *is* a width: height and content scale (0.92 / 1 / 1.08, clamped 0.9–1.1) follow `openWidth`, so the Layout slider keeps working and shows as Custom. Tab content is laid out at the 700 pt design size and scaled; the header stays at true size and is split around the notch, with tab buttons narrowing (30 → 22 pt) so nothing slides under the notch |
| Corner style, number font | ✅ v0.4 | Open bottom radius 16–36 pt, closed bottom radius 8–20 pt. SF Pro / SF Pro Rounded for clock, timers, stats, player title, compact clock and timer |
| Appearance pane + live preview | ✅ v0.4 | `Views/Settings/AppearancePane.swift`: the real `NotchRootView` with its own preview view model (open / now playing / HUD, any tab) over your desktop picture, updating instantly; theme cards, accent swatches, style cards, size / corners / font, reset to defaults |
| Themes: built-ins, JSON import / export | ✅ v0.4 | Midnight, Aurora (Glass), Paper (Minimal, Compact, Mono), Neon (Glow). `ThemeFile` JSON (`"format": "blinko-theme"`); unknown keys ignored, values clamped |

## 2. Performance budget

| Metric | Target | Measured |
|---|---|---|
| Idle CPU (island closed, nothing playing) | ≈ 0 % | v0.3: 0.01–0.07 s CPU per 30 s (≈ 0.0–0.2 %) with the default v0.3 features on (Focus, privacy, network, AirPods). v0.4 (Meeting mode + command bar on): 0.01 s per 30 s |
| Open island, idle | < 1 % | ~0.7 % (v0.1) |
| Media bridge (perl) idle | 0 % | 0.0 %, ~5 MB |
| RSS | < 80 MB | v0.3: ~63–66 MB idle; v0.4: ~64 MB idle |

Rules every feature must follow:
1. **Event-driven first.** IOKit / CoreAudio / CoreMediaIO / EventKit / IOBluetooth / NWPathMonitor / DispatchSource, never polling when an event exists. The only v0.3 polls: download sizes (2 Hz, only while a partial file exists) and the Focus Status fallback (20 s, only when no database access).
2. **Nothing runs unless someone can see it or the feature is on.** Stats, scrubber, camera, timeline views and lyrics fetching start with their views; weather/downloads/network/Focus/privacy stop entirely when switched off.
3. **Leaf-level observation.** `@Observable` services are read in the smallest view that needs them; the island frame never observes track data.
4. **Window size never depends on hover** (feedback-loop bug found and fixed during v0.1 profiling).
5. **Render-server animation** for anything continuous (Core Animation visualizer, download spinner).
6. **Bounded caches** (`NSCache`), decode images once and downsample them, keep I/O and network decoding off main.
7. Timers always carry `tolerance`; features turned off do no background work at all.

## 3. Roadmap

- **v0.2 — Polish (shipped).** Shuffle/repeat, ±10 s seek, swipe for tracks, Caps Lock + mic HUD, shortcut recorder, tab reordering, size tuning, Pomodoro, clock widget, DMG/notarization script, pointer monitors that only run near the island, pre-blurred artwork glow, Sparkle.
- **v0.3 — Awareness (shipped).** Focus/DND, camera/mic indicators, downloads activity, Wi-Fi/VPN/Hotspot alerts, AirPods battery, weather, synced lyrics, multiple timers, world clocks, Notes and Tools tabs (colour picker, Keep Awake), shelf expiry + multi-select drag-out, localisation infrastructure, reduced motion. Best-effort: AirPods levels, Focus without Full Disk Access; skipped: screen-recording indicator; postponed: LocalSend.
- **v0.4 — Power user.** Shipped: themes & island styles (accent, Classic/Minimal/Glass/Glow, size presets, corners, font, Appearance preview, theme import/export), Meeting mode (call detection, mute / leave card, best-effort "You're muted" warning), the ⌥Space command bar (calculator, units, currency, apps, Shortcuts, clipboard, shelf, Blinko actions, web). In progress: AI agent status and approvals (Claude Code / Codex hooks), URL scheme + CLI. Later: real FFT visualizer, AirPlay routing, DDC brightness for external displays, per-app volume, first translations.
- **v0.5 — Lock screen and notifications.** SkyLight lock-screen widgets; notification mirroring research.
- **v0.6 — Platform.** JavaScriptCore extension API and an extension gallery.
