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

### System status
| Feature | Status | Notes |
|---|---|---|
| Focus / DND indicator | 🟡 v0.3 | **Two sources.** With Full Disk Access: `~/Library/DoNotDisturb/DB` watched by a `DispatchSource` (fully event-driven, shows the mode's name and icon). Otherwise `INFocusStatusCenter` (authorize in Settings → Live Activities): on/off only; it has no change notification for regular apps, so it is re-read on app switches / wake plus one 20 s timer (10 s tolerance) that exists only while authorized and enabled. Scheduled Focus modes may be reported late on the second path |
| Camera / microphone in use | ✅ v0.3 | CoreMediaIO + CoreAudio `DeviceIsRunningSomewhere` listeners (default input re-attached on change, old listeners removed). Green / orange dots at the wing edge (or a small privacy wing when nothing else shows) + a transient activity on start. Blinko's own mirror is ignored |
| Screen-recording indicator | ⏭ | **Skipped:** no public, reliable "screen is being captured" signal (ScreenCaptureKit only reports your own streams). Revisit if macOS adds one |
| App notifications in the island | ⏭ v0.5 (no public API; research) | |
| AI coding-agent status + approvals (Claude Code hooks → socket) | ✅ v0.4 | **Agent Hub.** Unix socket in Application Support (0600, same-uid peers only, `DispatchSource` accept/read, nothing received is executed), NDJSON protocol in [AGENT_PROTOCOL.md](AGENT_PROTOCOL.md) so Codex/Cursor/scripts can report too. Claude Code via hooks (SessionStart, UserPromptSubmit, Pre/PostToolUse, PermissionRequest, Notification, Stop, SubagentStop, SessionEnd) installed from Settings → Agents: read → `settings.json.blinko-backup` → merge → atomic write; uninstall removes only Blinko's entries. Closed island: render-server spinner + project + tool, pulsing hand + "Approve?" when asked. Approval card auto-opens on the Agents tab (Approve ⌘↩ / Deny esc once clicked, "Answer in Terminal"); unanswered requests fall back to Claude Code's own prompt after 30 s–5 min (default 90 s), as does a missing Blinko. Agents tab lists sessions (state, last action, elapsed, cost). One work item flags sessions silent for 10 min |

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
| Snapshot renderer (`--snapshot <dir>`) for design QA | ✅ | v0.3 adds every new activity, tab and the busiest header |
| Customisable shortcut, reorderable / hideable tabs, island size tuning | ✅ v0.2 | Settings → General / Layout; new tabs are appended automatically |
| Lock-screen widgets (SkyLight space) | ⏭ v0.5 | Private API |
| Signed + notarized DMG (`scripts/release.sh`) | ✅ v0.2 | Needs a Developer ID cert + notary profile |
| Sparkle auto-updates | ✅ v0.2 | Appcast on GitHub Releases |
| Localisation | 🟡 v0.3 | **Infrastructure, English only.** `Resources/Localizable.xcstrings` (≈240 keys) generated from the code by `scripts/extract-strings.sh` (compiler `-emit-localized-strings` + `xcstringstool sync`, i.e. what Xcode does). `build.sh` compiles it into `<lang>.lproj` in the main bundle, so plain `Text("…")` / `String(localized:)` pick translations up without a SwiftPM resource bundle. Add a language by translating the catalog in Xcode |
| Extensions / plugins (JavaScriptCore) | ⏭ v0.6 | |

### Automation
| Feature | Status | Notes |
|---|---|---|
| `blinko://` URL scheme | ✅ v0.4 | `CFBundleURLTypes` + `kAEGetURL` handler registered in `applicationWillFinishLaunching` (a URL that launches Blinko is queued until the islands exist). `open?tab=`, `alert?title=&body=&icon=&color=&duration=` (custom transient activity: SF Symbol, colour name or `#RRGGBB`, 1–30 s), `timer?minutes=&label=`, `focus/start`, `focus/stop`, `shelf/add?path=` (repeatable, existing files only), `keepawake?minutes=` / `?off=1`. Parameters are data only |
| `blinko` CLI | ✅ v0.4 | Separate SwiftPM target bundled as `Contents/Helpers/blinko` (not `MacOS/`: "blinko" and "Blinko" collide on case-insensitive volumes). Automation commands open `blinko://` URLs via `open -g -b app.blinko.Blinko` (launches Blinko if needed); `hook` / `send` talk to the Agent Hub; `claude install|uninstall|status [--settings]`. Settings → Automation symlinks it into /usr/local/bin when writable, else ~/.local/bin (never sudo) |
| Shortcuts actions (App Intents) | 🟡 v0.4 | **Best-effort.** Show Alert, Start Timer, Start Focus, Open Island, Add to Shelf, Keep Awake (+ two App Shortcuts). SwiftPM doesn't run Xcode's metadata step, but the swift-build backend already emits `.swiftconstvalues`, so `scripts/appintents-metadata.sh` runs `xcrun appintentsmetadataprocessor` on them and bundles `Metadata.appintents` (validated: all six actions present). Not verified in the Shortcuts UI (no UI access during development); the script warns and skips without Xcode. Shortcuts' "Open URLs" and "Run Shell Script" with the URL scheme / CLI work regardless |

## 2. Performance budget

| Metric | Target | Measured |
|---|---|---|
| Idle CPU (island closed, nothing playing) | ≈ 0 % | v0.3: 0.01–0.07 s CPU per 30 s (≈ 0.0–0.2 %) with the default v0.3 features on (Focus, privacy, network, AirPods) |
| Open island, idle | < 1 % | ~0.7 % (v0.1) |
| Media bridge (perl) idle | 0 % | 0.0 %, ~5 MB |
| RSS | < 80 MB | v0.3: ~63–66 MB idle |

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
- **v0.4 — Power user.** AI agent status and approvals (Agent Hub: Claude Code hooks, open socket protocol for Codex/Cursor/scripts), `blinko://` URL scheme, `blinko` CLI and Shortcuts actions, real FFT visualizer, AirPlay routing, DDC brightness for external displays, per-app volume, first translations.
- **v0.5 — Lock screen and notifications.** SkyLight lock-screen widgets; notification mirroring research.
- **v0.6 — Platform.** JavaScriptCore extension API and an extension gallery.
