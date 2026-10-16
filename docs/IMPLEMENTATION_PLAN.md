# Ambient Desktop Pets — Implementation Plan

Source spec: [ambient-desktop-pets-requirements.md](ambient-desktop-pets-requirements.md)

## 0. Decisions locked in

| Topic | Decision | Consequence |
|---|---|---|
| Distribution | Personal / dev use only | No App Sandbox, no notarization. Any API is allowed. |
| Min OS | macOS 14 Sonoma | `@Observable`, `MenuBarExtra`, SwiftUI `Settings` scene, `NSView.displayLink` are all available. |
| Build | **SwiftPM only** (root `Package.swift` + local package `PetKit`), bundled by `make app`. No Xcode: the Command Line Tools are enough (decided 2026-10-12). | Engine logic is testable with `swift test`. Instruments is available for perf work. |
| Art | **Marvel Cosmic Invasion sprites** (one PNG per frame) from The Spriters Resource for Iron Man and Spider-Man, and the **SNES Batman Returns** sheet for Batman. Full source notes in [ART_SOURCES.md](ART_SOURCES.md). | Side view with real flight, beam/repulsor, walk, jump/fall and victory poses, so far less faking is needed. `petpack frames` keeps each frame's canvas anchor as the pivot; packed sheets (Batman) are sliced automatically with per-frame pivots. |
| Asset licensing | Ripped Capcom sprites of Marvel IP | **Personal use only.** Raw and generated art is **gitignored** and never published. The licensed fallback for any distribution is listed in ART_SOURCES.md. |
| Permissions | Accessibility + Screen Recording allowed | Precise UI avoidance (focused element frames) and window titles for meeting detection. Every feature **degrades gracefully** when a permission is missing. |
| Pet size | User-adjustable slider, 50–150 % of native sprite size, default 80 % | Scale is a runtime setting. Nearest-neighbor filtering keeps the pixel art crisp. |
| Speech bubbles | In V1, rare and short (2–3 s), toggleable | Per-pet `lines.json`. |
| Second pet (M6 proof) | Spider-Man | Exercises different motion primitives (drop on tether, cling to edge). |
| Plan depth | M1–M6 detailed, M7–M8 outlined | — |

### Deviations from the spec's roadmap order (and why)

1. **Data-driven pet packs start in M2, not M6.** Hardcoding Iron Man and extracting it later costs more than loading `pet.json` from day one. M6 then becomes registry + validation + the second-pet proof.
2. **Basic display selection lands in M1/M3, full multi-monitor in M4.** The §37 vertical slice already needs "random connected display".
3. **Generic motion and effect primitives Spider-Man needs (tether, edge-cling) are built in M2/M4** as engine features. M6's test is then honest: adding Spider-Man touches **zero Swift files**.


## Progress — 2026-10-11 (end of day)

**Status: M0–M8 implemented.** What's left needs hardware or an account: multi-display QA, the manual non-intrusion
checklist (`docs/QA.md`), and a live AI call (needs an API key).

| Milestone | State |
|---|---|
| M0–M3 vertical slice | Done. Built with SwiftPM + `make app`; no Xcode (by decision). |
| M4 multi-monitor | Done in code: display graph, `cross_display` (continuous or fade hop), hot-plug abort, Cross-Monitor Flight. Not tested on real multiple displays. |
| M5 context | Done: mic/camera-in-use, meeting window titles, full screen, games, presentations, reading heuristic, caret/pointer/active-window avoidance, mid-scene safety check, permissions UI + onboarding, synthesised sounds (off by default), debug overlay. |
| M6 framework | Done: user pack folder, validator, personality weights, per-pet on/off + weight, cursor reaction, `CREATING_A_PET.md`. Three pets: Iron Man & Spider-Man (Marvel Cosmic Invasion), Batman (SNES Batman Returns). |
| M7 pet-to-pet | Done: "together" appearances in screen lanes, plus ensemble scenes (`Pets/_ensembles`: Greeting, Race, Chase, Boo!, Dance-off) with `waitFor` sync and `partner` facing. |
| M8 AI | Done, opt-in: an AI picks among already-eligible scenes (structured output, 2 s hard timeout, rule-chooser fallback), generated line (sanitised, ≤40 chars / ~6 words, always shown), key in Keychain, window titles only if allowed. Also, in the same call: shared scenes / together appearances, routines composed from per-pet validated blocks (`blocks.json`, 2–5 blocks, duration-capped), daily moods (persisted per day, scale personality and frequency), and lines that use general stats (focus/away minutes, cameos today, weekday); each can be turned off. Providers: **OpenAI** Chat Completions (default, `gpt-6-luna`) or Anthropic Messages (`claude-haiku-5-5`); model editable. |

Deviations and notes:

- **Build:** SwiftPM (root `Package.swift`), `make app` bundles + ad-hoc signs. CLT quirks: swift-testing needs an
  explicit `-plugin-path` (the Makefile adds it); SwiftUI's `@State` macro plugin is missing, so the app uses
  `@Observable` objects instead.
- **Art:** ripped sheets live in `ThirdParty/source-assets/` (gitignored); `make art` rebuilds `Pets/*/sprites/sheet.png`.
  Two importers: `petpack slice` + `pack` (one big sheet) and `petpack frames` (one PNG per frame).
- **Engine additions beyond §3:** per-clip attachment points and `lean`; motions `swing` (pendulum, can attach to the
  screen top), `cling`, `cross_display`, `advance`; effects `tether_line`, `projectile`, `overlay`; per-pet `height`
  so every pet renders at the same size; display link from the scene's `NSScreen` (a view's link pauses off-screen).
- **Performance (sample/ps, Apple Silicon, 30 fps):** one pet ≈ 2.8–3.2 % of a core, three at once ≈ 9 %; idle 0 %.
  Memory ≈ 78 MB idle (mostly the SwiftUI/AppKit shell; sprite sheets are decoded only while on screen) and ≈ 140 MB
  peak with three pets. The 60 MB target is not met; the remaining baseline is the app framework itself.
- **Tests:** 127 PetCore unit tests + 8 PetPlatform integration tests (`make test`); `make validate-packs` checks every
  pack and ensemble.

---

## 1. Architecture

```
┌──────────────────────────── AmbientPets.app (thin AppKit/SwiftUI shell) ───────────────────────────┐
│  AppDelegate · MenuBarExtra · SettingsView · Onboarding (permissions) · LSUIElement (no Dock icon) │
└───────────────────────────────────────────────┬────────────────────────────────────────────────────┘
                                                │
┌──────────────────────── PetKit (local Swift package) ────────────────────────┐
│                                                                              │
│  PetCore (pure Swift, no AppKit — 100% unit-testable)                        │
│   ├─ Models: PetDefinition, SpriteAtlas, ClipDefinition, SceneDefinition,    │
│   │          StepDefinition, MotionSpec, EffectSpec, Personality, Policy     │
│   ├─ Scheduler (next-fire computation, gating)                               │
│   ├─ SceneSelector (filter → cooldown → weights → pick)                      │
│   ├─ ContextClassifier (signals → ContextState)                              │
│   ├─ SafeRegionPlanner (geometry: candidates − obstacles → scored regions)   │
│   ├─ EventHistory (Codable, persisted)                                       │
│   ├─ Clock / RandomSource protocols (injectable for tests)                   │
│   └─ PackValidator                                                           │
│                                                                              │
│  PetPlatform (AppKit / CoreAudio / AX / CG — macOS glue)                     │
│   ├─ PetEngine (@MainActor orchestrator)                                     │
│   ├─ ScreenManager (NSScreen, change notifications, coord conversion)        │
│   ├─ PetWindow (NSPanel, click-through) + PetWindowController                │
│   ├─ SceneDirector (runs a scene: resolves anchors → motion → clips → fx)    │
│   ├─ Rendering: PetRenderer protocol, SpriteRenderer (CALayer), Effects      │
│   ├─ Context monitors: ActiveApp, Idle, FullScreen, Meeting, Game, AXFocus,  │
│   │                    Thermal/Power, ScreenLock/Sleep                       │
│   ├─ AudioPlayer                                                             │
│   └─ PetRegistry (bundled + ~/Library/Application Support packs)             │
│                                                                              │
│  petpack (CLI executable): validate · slice · preview-info                   │
└──────────────────────────────────────────────────────────────────────────────┘
```

**Concurrency:** everything that touches AppKit runs on `@MainActor`. The work is tiny (one timer, one display link while a scene plays), so no background actors are needed. `PetCore` types are `Sendable` value types.

**Main loop:** there is none. The app is idle between appearances: one scheduled timer, plus event-driven context notifications and a ~10 s throttled sampler. A `CADisplayLink` exists **only while a scene is playing**, and the pet window is created at scene start and destroyed at scene end.

---

## 2. Repository layout

```
desktop-pets/
├── ambient-desktop-pets-requirements.md
├── IMPLEMENTATION_PLAN.md
├── Package.swift                    # app executable (SwiftPM), depends on Packages/PetKit
├── Makefile                         # make app | run | run-fg | test | validate-packs | art
├── App/
│   ├── AmbientPetsApp.swift         # @main, MenuBarExtra, Settings scene
│   ├── AppDelegate.swift            # engine bootstrap, lifecycle
│   ├── MenuBar/MenuBarContent.swift # Summon now · Pause 1h · Settings · Debug ▸ · Quit
│   ├── Settings/                    # SettingsView + tabs (General, Frequency, Behavior, …)
│   ├── Onboarding/PermissionsView.swift
│   ├── Info.plist                   # LSUIElement=YES
│   └── AmbientPets.entitlements     # no sandbox
├── Packages/PetKit/
│   ├── Package.swift
│   ├── Sources/PetCore/…
│   ├── Sources/PetPlatform/…
│   ├── Sources/petpack/main.swift
│   └── Tests/PetCoreTests/…
├── Pets/                            # bundled as a folder reference
│   ├── ironman/
│   │   ├── pet.json
│   │   ├── sprites/sheet.png        # generated by `petpack slice` from source assets (gitignored)
│   │   ├── sprites/atlas.json
│   │   ├── clips.json
│   │   ├── scenes/*.json
│   │   ├── lines.json
│   │   └── sounds/                  # CC0 sounds (e.g. Kenney), optional
│   └── spiderman/ …                 # M6
└── ThirdParty/source-assets/        # raw downloaded pack — gitignored, treated as data only
```

---

## 3. Pet pack format (defined in M2, frozen-ish in M6)

The pack is split into four layers so that art quality is independent of behavior:

1. **Atlas** (`sprites/atlas.json`): named frames with **variable rects and a pivot** (the feet or ground-contact point, in frame pixels). Fighting-game frames differ in size, so the renderer aligns frames on the pivot to stop jitter. A sprite's native facing (`"facing": "right"`) is mirrored for the opposite direction.
   ```json
   { "image": "sheet.png", "facing": "right",
     "frames": {
       "fly_0":  { "rect": [0,0,118,96],    "pivot": [58,90] },
       "walk_0": { "rect": [120,0,74,112],  "pivot": [36,110] } } }
   ```
   Grid-based sheets (Shimeji, itch packs) are also supported with `"grid": { "frameSize": [w,h] }` and a default pivot.
2. **Clips** (`clips.json`): an animation id → frames + fps + loop, plus an optional fallback chain. Scenes only ever reference clip ids.
   ```json
   { "walk":     { "frames": ["walk_right_0","walk_right_1","walk_right_2","walk_right_1"], "fps": 8, "loop": true, "mirrorForLeft": false },
     "hover":    { "frames": ["face_down_1"], "fps": 1, "loop": true },
     "fly_in":   { "fallback": "hover" },
     "salute":   { "fallback": "idle" } }
   ```
   If a sheet lacks a pose, the clip falls back (e.g. `hud_scan` → `idle` + `scanline` effect). A better sheet later just defines the clip properly. No scene changes needed.
3. **Scenes** (`scenes/*.json`): ordered steps. Each step combines a clip, a motion primitive, effects, and optional speech or sound.
   ```json
   { "id": "emergency_landing", "tier": "elaborate", "weight": 1.0,
     "tags": ["greeting","flashy"], "cooldownMinutes": 60,
     "allowedContexts": ["IDLE","ACTIVE_WORK"], "region": "bottom_edge",
     "steps": [
       { "clip": "fly",     "motion": { "type": "enter", "from": "top_offscreen", "to": "anchor", "curve": "easeOut" }, "duration": 2.5, "effects": ["thruster"], "sound": "whoosh" },
       { "clip": "idle",    "motion": { "type": "drop", "to": "ground" }, "duration": 0.6, "effects": ["dust_puff","squash"] },
       { "clip": "look",    "motion": { "type": "none" }, "duration": 1.5 },
       { "clip": "facing",  "motion": { "type": "none" }, "duration": 0.8, "effects": ["repulsor_flash"] },
       { "clip": "idle",    "motion": { "type": "hop" }, "duration": 1.0, "speech": { "pool": "praise", "chance": 0.3 } },
       { "clip": "fly",     "motion": { "type": "exit", "to": "top_offscreen", "curve": "easeIn" }, "duration": 2.0, "effects": ["thruster"] } ] }
   ```
4. **Pet manifest** (`pet.json`): identity, renderer kind (`"sprite"`), default scale, personality, capabilities, sound map, constraints (e.g. `"canFly": true`, `"groundOnly": false`).

**Motion primitives (engine-provided, generic):** `none`, `enter`/`exit` (from/to any edge or off-screen), `moveTo`, `walk` (along a ground line at px/s), `hover` (sine bob), `hop`, `drop` (gravity), `arc`, `path` (bezier through anchors), `tether_drop` (descend on a line from the screen top), `cling` (attach to a screen side edge, rotated), `cross_display` (route through displays).

**Effect primitives (engine-provided):** `thruster` (CAEmitterLayer particles), `repulsor_flash`, `beam`, `dust_puff`, `squash` (scale bounce), `tilt`, `scanline` (HUD scan overlay), `zzz`, `fade`, `tether_line` (web line), `speech_bubble`.

New pets compose these. Adding a *new primitive* is an engine change, and the plan accepts that.

---

## 4. Key technical approaches

### 4.1 Click-through, non-activating window (the hard requirement)
- `PetPanel: NSPanel` with `styleMask = [.borderless, .nonactivatingPanel]`, `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = false`, **`ignoresMouseEvents = true`**, override `canBecomeKey`/`canBecomeMain` → `false`, `hidesOnDeactivate = false`, `isReleasedWhenClosed = false`.
- `level = .statusBar` (above normal and floating windows, below system UI). `collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]`, so the pet isn't in Cmd-` / Mission Control, follows Spaces, and *can* appear over full-screen apps when policy allows it.
- Show with `orderFrontRegardless()`, **never** `makeKeyAndOrderFront` or `NSApp.activate`.
- App is `LSUIElement` (menu bar only, no Dock icon, never the active app during scenes).
- **Small moving window** (sized to sprite + effects padding) instead of full-screen overlays. This avoids 5K-sized transparent backing stores and lets one window cross display boundaries naturally. Position is updated by `setFrameOrigin` from the display-link tick.

### 4.2 Rendering
- `PetRenderer` protocol (`load(pack)`, `play(clip)`, `apply(effects)`, `setFacing`, `setScale`, `teardown`). V1 implements `SpriteRenderer`; `VectorRenderer` / `VideoRenderer` / `SceneKitRenderer` can come later behind the same protocol.
- `SpriteRenderer` uses a `CALayer` whose `contents` is set to pre-cut `CGImage` frames, with `magnificationFilter = .nearest` for crisp pixels. `contentsScale` is updated on `NSWindow.didChangeBackingPropertiesNotification` (crossing between Retina and non-Retina displays).
- Ticks come from `NSView.displayLink(target:selector:)` (macOS 14) with `preferredFrameRateRange` capped by the **Max FPS** setting (default 30). One tick advances the motion, the sprite frame and the effects. The display link is invalidated when the scene ends.
- Effects are cheap CA layers or emitters added to the same layer tree.

### 4.3 Coordinates and multi-display
- `ScreenManager` wraps `NSScreen.screens`, with ids from `CGDirectDisplayID` (`NSScreenNumber`), `frame`, `visibleFrame` (excludes menu bar and Dock) and `backingScaleFactor`. It refreshes on `NSApplication.didChangeScreenParametersNotification`.
- **One conversion utility** for AppKit (bottom-left origin, primary display) ↔ CG/AX (top-left origin) coordinates, heavily unit-tested. This is a classic bug source.
- Cross-display routes come from the display arrangement graph. Adjacent displays get a continuous flight. Non-adjacent ones (gaps, different heights) **fade out at one edge and fade in at the other**.
- If a display disconnects mid-scene, the scene aborts with a quick fade on the remaining screen.

### 4.4 Context detection (no high-frequency polling)
| Signal | Source | Permission | Cadence |
|---|---|---|---|
| Frontmost app | `NSWorkspace.didActivateApplicationNotification` | none | event |
| Idle time | `CGEventSource.secondsSinceLastEventType(.combinedSessionState, …)` | none | sampled every 10 s |
| Full-screen | `CGWindowListCopyWindowInfo` — frontmost app's layer-0 window bounds == display frame | none (bounds) | on app switch + every 10 s |
| Game | Target app's `LSApplicationCategoryType` contains `games`, plus a user-editable bundle-id list | none | on app switch |
| Meeting | Mic in use (CoreAudio `kAudioDevicePropertyDeviceIsRunningSomewhere` listener) **or** camera in use (CoreMediaIO equivalent) **or** known meeting app + window title match (Zoom "Zoom Meeting", Meet/Teams/Webex in browser tabs) | titles need Screen Recording | event (audio/cam) + on app switch |
| Presentation | Full-screen + Keynote/PowerPoint/Google Slides title match | Screen Recording for titles | on app switch |
| Focused element | `AXUIElementCopyAttributeValue(focusedElement, kAXFrame…)` for text fields and caret area | Accessibility | **only at scene spawn** and re-checked every ~1 s while a scene plays |
| Machine load | `ProcessInfo.thermalState`, `isLowPowerModeEnabled` | none | notifications |
| Lock / sleep | `com.apple.screenIsLocked`/`Unlocked` distributed notifications, `NSWorkspace.willSleep/didWake` | none | event |

`ContextClassifier` (pure, in PetCore) maps signals → `ACTIVE_WORK | READING | IDLE | FULL_SCREEN | PRESENTATION | VIDEO_CALL | GAMING | LOCKED`. READING is a heuristic: no keystrokes for ~30 s but recent scroll or mouse activity, or a browser/PDF/docs app frontmost.

`PolicyTable` (settings-backed, user-overridable) maps state → `{ paused, frequencyMultiplier, allowedTiers, audioAllowed, preferredRegions }`, following spec §10.

### 4.5 Scheduling and selection
- Next fire = `uniform(min, max) × contextMultiplier × personality.activityFactor`, clamped by cooldown. A single `Task.sleep`/`DispatchSourceTimer` handles it, and it is **recomputed** on wake, unlock and settings change.
- At fire time the **gates** are: enabled → not in quiet hours (spans midnight correctly) → not locked → daily limit → policy not paused → thermal state < `.serious`. If a gate fails, retry after a short backoff (60–120 s) instead of waiting a full interval, so the pet still shows up soon after a meeting ends.
- `SceneSelector` follows spec §31: candidates (all loaded pets × scenes) → drop if the context or capability isn't allowed → drop if in cooldown → tier roll (quick 60 / funny 25 / elaborate 10 / rare 5, tiers individually toggleable) → weight × personality tag multipliers × anti-repeat penalty (history) → pick.
- Rare events get **independent** cooldowns (e.g. each rare scene at most once per 48 h).
- `EventHistory` (JSON in `~/Library/Application Support/AmbientPets/history.json`) records lastScene, lastPet, lastScreen, lastAppearance, per-scene counts and timestamps, and rare history. It is capped (last 200 events).
- `Clock` and `RandomSource` (seeded) are injected, so scheduler and selector tests are deterministic.

### 4.6 Safe-region planning (spec §13)
`SafeRegionPlanner` (pure geometry) takes per-display `visibleFrame`, the obstacle rects and the scene's preferred region. It returns scored spawn anchors and paths.
- Candidates in priority order: edges (bottom strip above the Dock, sides, top below the menu bar) → corners → empty desktop areas (from CGWindowList bounds) → title-bar strips → outside the active window → random.
- Obstacles: the focused element / caret rect (AX), the frontmost window's content area (lower score, not forbidden), a cursor neighborhood (~150 px), and video/presentation windows (blocked entirely).
- During a scene, if the user's caret moves into the pet's path, the pet **shortens the scene** (jumps to its exit step).

### 4.7 Permissions UX
- First-run onboarding explains each permission and what degrades without it. Nothing is required, and the app works with zero grants.
- **Signing note:** ad-hoc rebuilds change the code signature, and macOS then silently drops Accessibility and Screen Recording grants. Sign Debug builds with your free **Apple Development** personal-team certificate (stable identity) so TCC grants survive rebuilds.
- Newer macOS versions periodically re-confirm Screen Recording. The app detects a lost grant (`CGPreflightScreenCaptureAccess`) and falls back to mic/cam/bundle-id meeting detection without nagging.

---

## 5. Milestones

Rough effort figures are for one developer pairing with Claude and are only indicative.

### M0 — Project bootstrap (~0.5 day)
- [x] ~~Install Xcode and XcodeGen~~ *(dropped 2026-10-12: SwiftPM + Command Line Tools are enough)*
- [x] `git init`, `.gitignore` (`*.xcodeproj`, `ThirdParty/source-assets/`, `Pets/*/sprites/sheet.png`, DerivedData).
- [x] Root `Package.swift`: app target `AmbientPets` (macOS 14, LSUIElement via `App/Info.plist`, no sandbox), depending on local package `PetKit`. *(replaces the XcodeGen `project.yml`)*
- [x] `Packages/PetKit` with targets `PetCore`, `PetPlatform`, `petpack`, `PetCoreTests` (Swift 6 language mode, strict concurrency).
- [x] `Makefile`: `app`, `build`, `run`, `run-fg`, `test`, `validate-packs`, `art`.
- [x] **You:** download the Iron Man and Spider-Man sheets listed in [ART_SOURCES.md](ART_SOURCES.md) into `ThirdParty/source-assets/<source>/`. The site blocks automated downloads, so this needs a browser. *(done: Cosmic Invasion Iron Man and Spider-Man; SNES + Genesis Batman)*

**Exit:** `make test` and `make run` produce a menu bar icon with a Quit item.

### M1 — Pet window (~1.5 days)
- [x] `PetPanel` per §4.1, plus `PetWindowController` (create, position, show, hide, destroy).
- [x] `ScreenManager` v1: list screens, `visibleFrame`, random screen, change notifications. Coordinate conversion util + tests.
- [x] Menu bar: **Summon (static)** places a placeholder image (a pack frame or a colored square) at a chosen screen's bottom-right edge for 5 s.
- [x] Debug menu: "Outline pet window" draws a 1 px border to visualize the frame.
- [x] Non-intrusion QA checklist (kept in `docs/QA.md` and re-run every milestone):
  - typing in TextEdit/VS Code continues uninterrupted while the pet shows
  - clicking a button *under* the pet activates the button
  - frontmost app doesn't change (`NSWorkspace.frontmostApplication` logged before/after)
  - pet is absent from Cmd-Tab, Cmd-`, and Mission Control window thumbnails
  - window drag beneath the pet works
  - appears over a full-screen app when the debug override is on

**Exit:** spec M1 success criterion. A visual pet appears over any app without interfering.

### M2 — Animation + pack format (~4 days)
- [x] `petpack slice` (pure CoreGraphics/ImageIO, input treated as data):
  1. Key out the sheet's background colour (auto-detected from the corner pixel, or `--bg #RRGGBB`) to alpha.
  2. Find sprite bounding boxes by connected-component detection, merging components that are close together (detached effects, gaps).
  3. Write numbered candidate frames + a **contact sheet PNG** (each frame drawn with its index) for labelling.
  4. From a small `labels.json` (`"fly": [12,13,14,13]`, `"walk": [3,4,5,6]`…), pack only the used frames into a compact `sheet.png` + `atlas.json`, with an auto pivot (bottom-centre of opaque pixels) that can be overridden per frame.
- [x] `petpack preview <pet> <clip>`: writes an animated GIF of a clip, for quick checks of pivots and timing.
- [x] PetCore models: `PetDefinition`, `SpriteAtlas`, `ClipDefinition` (with fallback chain), `SceneDefinition`, `StepDefinition`, `MotionSpec`, `EffectSpec` (all `Codable`, unknown-field tolerant, versioned with `"formatVersion": 1`).
- [x] `PetRenderer` protocol + `SpriteRenderer` (§4.2), display-link loop, FPS cap, nearest-neighbor scaling, pivot-aligned frame placement, mirroring for facing, **size slider** support (50–150 %).
- [x] `SceneDirector`: resolves anchors via a simple planner (bottom edge only for now), runs steps sequentially, interpolates motion with easing, triggers effects, and finishes with a guaranteed teardown (window closed, display link invalidated).
- [x] Motion primitives: `none, enter, exit, moveTo, walk, hover, hop, drop, arc`. Effects: `thruster, repulsor_flash, beam, dust_puff, squash, tilt, fade, scanline, zzz, speech_bubble`.
- [x] Speech bubble: small, rounded, auto-sized label above the pet, 2–3 s, from `lines.json` pools (e.g. `praise: ["Good work, sir.", "Systems nominal.", …]` — original lines).
- [x] Iron Man pack v1 *(Marvel Cosmic Invasion art)*: label the frames into clips (`idle, walk, fly, hover, landing, takeoff, repulsor, beam, salute` (victory pose), `fall, confused` (hit pose)). Fallbacks cover `look_*`, `hud_scan`, `sleep`, `dance`. Then scenes **Fly Across Screen**, **Emergency Landing**, **Edge Peek**, **Random Walk**, **Repulsor Test**, **HUD Scan**. *(Later: Fly Across merged into Cross-Monitor Flight, which is the same flight on one display; added Crash Landing, Rocket Punch and Energy Shield from the unused knockdown / dash-punch / parry animations)*
- [x] Menu bar **Summon ▸ <scene>** to play any scene on demand (dev loop).

**Exit:** spec M2. Iron Man flies in (thruster trail), lands with a dust puff, looks around, flashes a repulsor, salutes (hop + optional bubble), and flies out. CPU drops to ~0 % after exit.

### M3 — Scheduler (~2.5 days)
- [x] `Clock`, `RandomSource` protocols; `Scheduler` per §4.5 (min/max interval, cooldown, daily limit, quiet hours incl. overnight ranges, backoff).
- [x] `SceneSelector` with tiers, weights, cooldowns, anti-repeat, rare-event cooldowns.
- [x] `EventHistory` persistence.
- [x] Random display selection: uniform across connected displays (spec §5), with a weighting option added later if wanted.
- [x] `SettingsStore` (`@Observable`, UserDefaults-backed Codable) + SwiftUI **Settings**: General, Frequency, Behavior tiers, Audio placeholders, Quiet hours, Performance (FPS, pet size, reduce quality).
- [x] Menu bar: Pause for 1 h / until tomorrow, "Next appearance in ~X min" (debug).
- [x] Launch at login via `SMAppService.mainApp`.
- [x] Unit tests: interval distribution bounds, quiet-hours edges (22:00–08:00 across midnight, DST), daily-limit reset, cooldown exclusion, tier distribution over 10k seeded rolls (±2 %), no immediate repeats.

**Exit:** spec M3. Pet makes occasional cameos on its own. **This completes the §37 vertical slice.** Live with it for a few days before continuing, since that's the real UX validation.

### M4 — Multi-monitor (~2.5 days)
- [x] ScreenManager v2: display arrangement graph (adjacency by shared edges), per-display scale handling, hot-plug during a scene (abort and fade).
- [x] `cross_display` motion: route planning, continuous flight across adjacent displays, fade-hop across gaps. Correct `contentsScale` swap at the boundary.
- [x] Iron Man **Cross-Monitor Flight** scene (tier: elaborate; requires ≥2 displays, filtered otherwise).
- [x] Generic primitives for later pets: `tether_drop`, `cling`, `tether_line` effect (built and tested here with a debug scene). *(`tether_line`, `cling` and pendulum `swing` built; `tether_drop` = `enter` + `tether_line`)*
- [ ] QA: mixed Retina + non-Retina, vertical stacking, display unplugged mid-flight, clamshell mode. *(needs real multi-display hardware; geometry is unit-tested)*

**Exit:** spec M4. Pet appears on, and travels across, multiple displays.

### M5 — Context awareness (~4 days)
- [x] Monitors per §4.4: ActiveApp, Idle, FullScreen, Game, Meeting (mic/cam + titles), Presentation, AXFocus, Thermal/Power, Lock/Sleep, each behind a protocol for testability.
- [x] `ContextClassifier` + `PolicyTable` with spec §10 defaults. Settings → **Context** tab: per-state overrides, editable lists for game, meeting and presentation bundle ids.
- [x] `SafeRegionPlanner` full version (§4.6) wired into SceneDirector, plus mid-scene caret-collision early exit.
- [x] Permissions onboarding + status indicators in Settings (granted / missing / what's degraded).
- [x] Audio: `AudioPlayer` (AVAudioPlayer pool), CC0 sounds (whoosh, landing, repulsor, footsteps, HUD blip), **off by default**, volume, "only when idle", "never in meetings". Quiet hours mute everything.
- [x] Debug overlay (menu toggle): current ContextState, candidate regions and obstacle rects drawn on a transparent debug window.
- [x] Performance pass (§6 targets) *(with `sample`/`ps` instead of Instruments, which needs Xcode; results in Progress)*
- [x] Tests: classifier truth table, policy overrides, planner geometry (obstacle subtraction, edge preference, multi-display).

**Exit:** spec M5. A Zoom call with the mic on means zero appearances. Full-screen Keynote means zero. A game means zero. While you type in VS Code, cameos are rarer, shorter, at edges, and never over the caret. When idle, pets appear more often with longer scenes.

### M6 — Pet framework + Spider-Man (~3 days)
- [x] `PetRegistry`: loads bundled `Pets/*` plus user packs from `~/Library/Application Support/AmbientPets/Pets/*`. Per-pet enable toggle and weight in Settings.
- [x] `PackValidator` (PetCore) + `petpack validate <dir>`: schema version, atlas frames exist, clip fallbacks resolve without cycles, scenes reference known clips/primitives/effects/sounds, required capabilities, durations within 3–30 s. Invalid packs are skipped with a logged reason, never crash.
- [x] Personality applied in selection: tag multipliers (`mischievousness` → `surprise`, `friendliness` → `greeting`, `interaction` → `cursor` tags) and an activity factor on frequency.
- [x] Cursor reaction: `look_at_cursor` clip resolution from `NSEvent.mouseLocation` read inside the display-link tick (no global event monitor, no permission). Respects the "React to cursor" setting.
- [x] **Spider-Man pack, data only:** slice the Spider-Man frames (swing, wall-crawl, web-shot, crouch, victory frames), plus scenes Drop From Top (`tether_drop` + `tether_line`), Wall Cling (`cling` on a side edge), Swing Across (`arc` + `tether_line`), Edge Peek. *(Marvel Cosmic Invasion art via `petpack frames`; 14 scenes incl. Drop From Top, Wall Cling, Swing Across, Edge Peek. Needed engine work, so the zero-Swift-changes exit criterion was not met)*
- [x] `docs/CREATING_A_PET.md`: the pack format reference and a step-by-step guide for adding a new pack character.

**Exit:** spec M6. `git diff --stat` for the Spider-Man commit touches only `Pets/spiderman/**` (and docs). No `.swift` files change.

### M7 — Pet-to-pet (outline, ~4–5 days)
- Allow up to N concurrent `SceneDirector`s (default 2), each with its own window.
- **Ensemble scenes:** a scene file with `roles: [{petTag: "flyer"}, {petTag: "climber"}]` and per-role step tracks sharing a timeline. Sync points (`"waitFor": "role2.step3"`) handle coordination.
- Meeting points: both pets walk to anchors computed relative to each other. Facing is resolved automatically.
- Scenes: greeting, race, chase, synchronized dance, one scares the other. Selected only when ≥2 compatible pets are enabled. Treated as rare-tier by default.
- Selector picks role-compatible pets via tags, so there are no hardcoded pet pairs.

### M8 — Optional AI (outline, ~4–6 days)
- `SceneChooser` protocol: `RuleChooser` (default, M3–M6 logic) and an opt-in `LLMChooser`. The LLM sees only the **already-filtered** candidate list plus a compact context summary (state, app category, time of day, recent history, personality) and returns a scene id + optional speech line. Its output is validated against the candidates, and the rule chooser is the fallback on timeout (≤2 s) or invalid output.
- All non-intrusion gates run **before** the LLM is consulted, so it can never bypass pauses, quiet hours or limits.
- Generated speech: length-capped, profanity-filtered, and the same rare frequency as authored lines.
- Privacy: off by default. Window titles are never sent unless explicitly enabled. API key in Keychain.
- Default model: latest Claude (e.g. `claude-haiku-5-5` for low latency and cost), called at most once per appearance.

---

## 6. Performance budget (verified with Instruments in M5)

| Metric | Target |
|---|---|
| CPU, idle between appearances | ≈0 % (no display link, no window; ≤1 wakeup / 10 s) |
| CPU, during a scene @30 fps | < 3 % of one core on Apple Silicon |
| Memory | < 60 MB resident |
| GPU | no measurable impact (small layer, no full-screen surfaces) |
| Under load | skip appearances when `thermalState ≥ .serious` or Low Power Mode is on (configurable) |

---

## 7. Testing strategy
- **Unit (PetCore, `swift test`):** scheduler, gates, quiet hours, selector distributions (seeded), cooldowns, history, classifier, policy, planner geometry, coordinate conversion, pack decoding, validator.
- **Integration (PetPlatform, XCTest in app host):** SceneDirector runs a scene against a fake clock and asserts the window is torn down. Registry loads fixture packs.
- **Manual QA (`docs/QA.md`):** the non-intrusion checklist from M1, plus multi-monitor, context, and sleep/wake/lock cases. Re-run at each milestone exit.
- **Pack CI-ish:** `make validate-packs` runs `petpack validate` on every bundled pack.

---

## 8. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Ripped sheets are irregular (varying sizes, stray effect pixels, shared palettes) | Auto-slice + contact sheet + manual labels, per-frame pivot overrides, `petpack preview` GIFs for checking. |
| Sheet layout or poses differ from expectations | Confirm right after download (M0). Clip fallbacks + effects cover any missing poses. |
| Capcom/Marvel IP | Personal use only, gitignored. Licensed fallback (moxica jetpack hero) noted in ART_SOURCES.md. |
| TCC grants reset on rebuild | Stable personal-team signing identity (§4.7). |
| Screen Recording re-prompts | Graceful fallback to mic/cam/bundle-id detection. |
| Coordinate-space bugs across displays | Single conversion util + unit tests + debug overlay. |
| Window steals focus in an edge case (e.g. after Spaces switch) | `nonactivatingPanel` + `canBecomeKey=false` + automated "frontmost app unchanged" assertion in debug builds. |
| Meeting heuristics miss a case | Mic/camera-in-use is the strong signal and catches almost all calls. Plus a "Pause for 1 h" menu item. |

---

## 9. Immediate next steps
1. Download the sheets listed in [ART_SOURCES.md](ART_SOURCES.md) into `ThirdParty/source-assets/`.
2. M0 scaffold (`Package.swift`, Makefile, skeleton targets).
3. Inspect the real sheets (background colour, packing, poses available), then write `petpack slice`.
4. M1 → M3 to reach the vertical slice, then live with it for a few days before M4.
