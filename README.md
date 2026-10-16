# Ambient Desktop Pets

A macOS menu-bar app that makes short, click-through cameos of pixel-art pets (Iron Man, Spider-Man, Batman,
Captain America, Black Panther, Cosmic Ghost Rider, Hela, Thanos) over
your desktop, without stealing focus. Pets stay away during meetings, presentations, full-screen apps and games, keep
clear of your text cursor, can appear together and interact, and can optionally let an AI (OpenAI or Claude) pick
what happens next.
Spec: [docs/ambient-desktop-pets-requirements.md](docs/ambient-desktop-pets-requirements.md) ·
Plan: [docs/IMPLEMENTATION_PLAN.md](docs/IMPLEMENTATION_PLAN.md) · QA: [docs/QA.md](docs/QA.md)

## Build and run

Requirements: macOS 14+ and the Xcode **Command Line Tools** (Swift 6). Full Xcode is not needed.

```bash
make run          # build build/AmbientPets.app and launch it (menu bar ✨ icon, no Dock icon)
make run-fg       # same, in the foreground of this terminal
make test         # PetCore unit tests (swift-testing)
make validate-packs
```

The app is built with SwiftPM (`Package.swift` at the root, engine in `Packages/PetKit`); `make app` wraps the binary
into a signed `.app` bundle.

Signing: `make` uses your "Apple Development" certificate if one is installed, otherwise ad-hoc. Ad-hoc rebuilds
change the signature, so macOS forgets Accessibility / Screen Recording grants on every build (matters from M5 on).

## Dev loop

| | |
|---|---|
| Menu ▸ **Summon ▸ \<pet\> ▸ \<scene\>** | play any scene now, on the display under the mouse |
| Menu ▸ **Summon Together** | several enabled pets at once, each in its own part of the screen |
| Menu ▸ **Pets** | Mix of enabled pets / Only one pet, per-pet toggles, how often they come together |
| Menu ▸ **Summon Interaction ▸ \<scene\>** | a shared scene (Greeting, Race, Chase, Boo!, Dance-off) |
| Menu ▸ **Debug ▸ Show Context Overlay** | draws the context state, obstacles (caret red, pointer orange, window blue) and planner spots |
| Menu ▸ **Debug** | static pet (M1 check), fire scheduler now, outline pet window, context/gate status |
| `--summon ironman/emergency_landing` | play a scene at launch (`--summon all` every scene, `--summon batman` one pet's scenes, `--summon together`) |
| `--summon ensemble:greeting` | play a shared scene at launch |
| `--context-probe` | print what the context monitors see (state, meeting, full screen, obstacles, permissions) and quit |
| `AMBIENT_PETS_DEBUG=1` | print tick count / fps per scene to stderr |
| `AMBIENT_PETS_SNAPSHOT_EVERY=0.3` | with `AMBIENT_PETS_SNAPSHOT_DIR`, also snapshot every N seconds (frame sequences) |
| `AMBIENT_PETS_SNAPSHOT_DIR=/path` | render the pet layer tree to PNG at each step (no Screen Recording needed) |
| `AMBIENT_PETS_DIR=/path` | extra pet-pack directory, searched first |

```bash
AMBIENT_PETS_DEBUG=1 build/AmbientPets.app/Contents/MacOS/AmbientPets --summon all
```

## Settings worth knowing

- **Context** — what pauses pets (full screen, meetings, games), keep-away from the caret / pointer, how often per
  activity (working / reading / away), editable meeting / presentation / game / reading app lists.
- **Permissions** — both optional. Accessibility enables caret avoidance; Screen Recording lets meeting detection read
  window titles (Meet / Teams in a browser). Microphone and camera *use* are detected without either.
- **Behavior ▸ Audio** — synthesised sounds (`tools/make_sounds.py`), off by default, never while working or in
  meetings, muted in quiet hours.
- **AI** — off by default. With an **OpenAI** (default, model `gpt-6-luna`) or **Anthropic** API key (stored in the
  Keychain), one call per cameo (2 s limit, otherwise the normal picker runs) can:
  - pick among scenes that already passed every rule, and write a short line about the general context
    ("45 minutes in, take a sip of water");
  - choose a shared scene or a together appearance when several pets come out;
  - invent a short routine from each pet's validated moves (`blocks.json`), so the same pet does new things;
  - give each pet a mood for the day (cheerful, playful, mischievous, focused, brooding, sleepy) that shifts its
    personality and how often it shows up.

  Saving a key turns the AI on; **Summon Now** also goes through it, so you can try it from the menu. The AI is
  asked once per situation (activity, part of the day, each 45 minutes of focus, coming back after a break, or
  today's moods); other cameos use the normal picker and the pets' own lines. When the AI writes a line (at most
  about six words), the pet says it, pausing until it's been read. Settings ▸ AI ▸ Usage counts calls (today and
  all time, answered / failed / skipped, tokens) and lists the last 20; the menu shows today's count. Each call is
  also in the system log: `log show --last 1d --predicate 'subsystem == "dev.jefflabs.AmbientPets"' | grep "AI call"`. Each of these has its own toggle in Settings ▸ AI. It sends only the activity, app category, time of day and weekday,
  minutes focused or away, cameos today, recent scenes, moods and the candidate scenes and moves (window titles only
  if you allow it). Try a routine without a key: `AmbientPets --summon routine:ironman:repulsor_shot,celebrate`.

## Art

Sprites are ripped game art (personal use only) listed in [docs/ART_SOURCES.md](docs/ART_SOURCES.md). The downloads
live in `ThirdParty/source-assets/` and the generated `sheet.png` files are gitignored; only frame picks
(`Pets/*/sprites/labels.json`), atlases and behaviour are in the repo. `make art` (run by `make app`) rebuilds sheets:

- **Iron Man**, **Spider-Man**, **Captain America**, **Black Panther**, **Cosmic Ghost Rider**, **Hela** and **Thanos**:
  Marvel Cosmic Invasion per-frame PNGs → `petpack frames` with `labels.json`
  (`"idle": ["Idle_*"]`, overlays like `"Idle_00.png+Spidersense_*"`, effects from `../effects/…`), one shared canvas
  anchor as the pivot (`pivotByClip`: `center` for projectiles, `left` for beams).
- **Batman**: SNES Batman Returns sheet → `petpack slice` (numbered candidates) → `petpack pack` with `labels.json`
  (frame indices per clip, `flip` for mixed facings, `pivotByClip: torso` for a steady walk).

Every `pet.json` sets `"height"`: the character's standing height in sprite px. The engine scales each pet so a
standing pet is 135 pt tall at 100 % (108 pt at the default 80 %), so pets from different games match side by side.
The values are tuned by eye in a side-by-side render (Iron Man 82: his idle hovers on jets; Spider-Man 62: he
crouches; Batman 78: his ears and cape add height but he's slim), so all three look the same size together. The two bosses are
set a little short on purpose (Hela 94, Thanos 92) so they stand taller than the heroes.

Then merge `sprites/clips.suggested.json` into `clips.json` (fps, loop, attachment points like `hand` / `web` /
`thruster`), check with `petpack preview <pet> <clip> --out strip.png`, and `make validate-packs`.
Without the downloads, `make placeholder-art` generates original stand-in Iron Man sprites to test the pipeline.

## Layout

```
App/                      thin SwiftUI/AppKit shell: MenuBarExtra, Settings, AppDelegate
Packages/PetKit/
  Sources/PetCore/        pure Swift: pack models, scheduler, selector, history, geometry, validator, slicer
  Sources/PetImaging/     CoreGraphics/ImageIO helpers (PNG/GIF, sheet packing, contact sheets)
  Sources/PetPlatform/    AppKit: click-through panel, sprite renderer, effects, SceneDirector, PetEngine
  Sources/petpack/        CLI: validate · slice · pack · preview · placeholder · info
  Tests/PetCoreTests/
Pets/<id>/                pet packs: pet.json, clips.json, scenes/*.json, lines.json, sprites/
```
