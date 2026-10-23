# Blinko — Feature Matrix & Roadmap

Research basis (Oct 2026): boring.notch, Atoll, MewNotch, NotchDrop, DynamicNotchKit, jackson-storm/DynamicNotch,
Cyclop, SuperIsland, ComfyNotch, vibe-notch / notchi (agent status), plus closed-source NotchNook and Alcove.

Legend: ✅ shipped in v0.1 · 🟡 partial · ⏭ planned

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
| Synced lyrics (LRCLIB) | ⏭ v0.3 | |
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
| AirPods battery levels | ⏭ v0.3 | |
| Wi-Fi / VPN / Hotspot alerts | ⏭ v0.3 | |

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
| Multiple concurrent timers | ⏭ v0.3 | |
| Clock: Home widget, header time, idle clock in closed island | ✅ v0.2 | `TimelineView(.everyMinute)`, only while visible |
| World clocks (second time zone) | ⏭ v0.3 | |
| Notes / snippets, color picker, caffeinate | ⏭ v0.3 | |
| Weather | ⏭ v0.3 | Open-Meteo, no key |
| Shelf expiry, LocalSend, multi-select drag-out | ⏭ v0.3 | |
| Downloads progress live activity | ⏭ v0.3 | FSEvents on ~/Downloads |

### System status
| Feature | Status |
|---|---|
| Focus / DND indicator | ⏭ v0.3 |
| Screen-recording / camera / mic privacy indicators | ⏭ v0.3 |
| App notifications in the island | ⏭ v0.5 (no public API; research) |
| AI coding-agent status + approvals (Claude Code hooks → socket) | ⏭ v0.4 |

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
| Settings window, onboarding, menu bar icon, launch at login | ✅ | |
| Snapshot renderer (`--snapshot <dir>`) for design QA | ✅ | |
| Customisable shortcut, reorderable / hideable tabs, island size tuning | ✅ v0.2 | Settings → General / Layout |
| Lock-screen widgets (SkyLight space) | ⏭ v0.5 | Private API |
| Signed + notarized DMG (`scripts/release.sh`) | ✅ v0.2 | Needs a Developer ID cert + notary profile |
| Sparkle auto-updates | ⏭ | Pending decision on dependency + appcast hosting |
| Extensions / plugins (JavaScriptCore) | ⏭ v0.6 | |
| Localisation, reduced-motion | ⏭ v0.3 | |

## 2. Performance budget

| Metric | Target | v0.1 measured |
|---|---|---|
| Idle CPU (island closed, nothing playing) | ≈ 0 % | ~0.2 % (v0.2: no wakeups for mouse movement away from the island) |
| Open island, idle | < 1 % | ~0.7 % |
| Media bridge (perl) idle | 0 % | 0.0 %, ~5 MB |
| RSS | < 80 MB | ~75 MB |

Rules every feature must follow:
1. **Event-driven first.** IOKit / CoreAudio / EventKit / IOBluetooth / distributed notifications, never polling when an event exists.
2. **Nothing runs unless someone can see it.** Stats, scrubber, camera and timeline views start in `onAppear` and stop in `onDisappear`.
3. **Leaf-level observation.** `@Observable` services are read in the smallest view that needs them; the island frame never observes track data.
4. **Window size never depends on hover** (feedback-loop bug found and fixed during v0.1 profiling).
5. **Render-server animation** for anything continuous (Core Animation visualizer).
6. **Bounded caches** (`NSCache`), decode images once and downsample them, keep I/O off main.
7. Timers always carry `tolerance`; features turned off do no background work at all.

## 3. Roadmap

- **v0.2 — Polish (shipped).** Shuffle/repeat, ±10 s seek, swipe for tracks, Caps Lock + mic HUD, shortcut recorder, tab reordering, size tuning, Pomodoro, clock widget, DMG/notarization script, pointer monitors that only run near the island, pre-blurred artwork glow. Sparkle pending.
- **v0.3 — Awareness.** Focus/DND, privacy indicators, downloads activity, Wi-Fi/VPN/Hotspot alerts, AirPods battery, weather, synced lyrics, notes and snippets, shelf expiry, localisation, reduced motion.
- **v0.4 — Power user.** AI agent status and approvals (Claude Code / Codex hooks), real FFT visualizer, AirPlay routing, DDC brightness for external displays, per-app volume.
- **v0.5 — Lock screen and notifications.** SkyLight lock-screen widgets; notification mirroring research.
- **v0.6 — Platform.** JavaScriptCore extension API and an extension gallery.
