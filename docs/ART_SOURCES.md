# Art Sources

Record of the sprite art used, or considered, for each pet. Update it whenever art is added or swapped.

> **Licensing:** every Marvel character source below is ripped game art or fan art of IP owned by Marvel/Disney (and Capcom for the game sprites). It is fine for **personal use only**. Raw and derived files stay under `ThirdParty/source-assets/` and generated `Pets/*/sprites/`, both **gitignored**. Never commit, publish, or distribute them. Replace them with original or licensed art before any sharing.

> **Download note:** The Spriters Resource blocks automated downloads (HTTP 403), so these files have to be downloaded manually in a browser. Put each download in its own folder under `ThirdParty/source-assets/<source-name>/`.

## Chosen

### Spider-Man — Marvel Cosmic Invasion (Tribute Games / Dotemu, PC), via The Spriters Resource
- "PC / Computer - Marvel Cosmic Invasion - Playable Characters - Spider-Man" (zip). Credits in the zip's `Tag.txt`.
- One PNG per frame on a shared 256×256 canvas, named by animation (Idle, Walk, Sprint, Jump, Land, Webswing,
  Selectscreen = hanging upside-down on a web, Spidersense overlay, …), 10 colour variants. Only the Default suit is used.
- Downloaded: ☑ 2026-10-11 → `ThirdParty/source-assets/cosmic-spiderman/default/` (+ `Web*.png`, `Tag.txt`).
- In use: `petpack frames Pets/spiderman/sprites/labels.json`, which keeps the canvas anchor as every frame's pivot.

### Iron Man (in use) — Marvel Cosmic Invasion (Tribute Games / Dotemu, PC), via The Spriters Resource
- "PC / Computer - Marvel Cosmic Invasion - Playable Characters - Iron Man" (zip). Same game as Spider-Man, so the two
  match in style and scale. Credits in `ThirdParty/source-assets/cosmic-ironman/Tag.txt`.
- Downloaded: ☑ 2026-10-11 → `cosmic-ironman/default/` (406 frames, Default suit) + `cosmic-ironman/effects/` (115 frames:
  Proton Cannon beam, repulsor bolt, charged orb, ground-slam shockwave). 10 colour variants in the zip are unused.
- In use: `petpack frames Pets/ironman/sprites/labels.json`. He always flies in this game (idle hovers on jets; Sprint is
  real flight). "Special" is the Proton Cannon (shoulder cannon + beam); Selectscreen is a suit-up (helmet closes).

### Batman — Batman Returns (SNES), via The Spriters Resource
- "SNES - Batman Returns - Playable Characters - Batman" (sheet upgraded by DAD34853), `#A34D4D` background.
- Downloaded: ☑ 2026-10-11 → `ThirdParty/source-assets/snes-batman/sheet.png` (900×1650).
- In use: sliced with `--bg '#A34D4D' --merge 1 --min-pixels 40` (107 candidates); picks in `Pets/batman/sprites/labels.json`
  (walk, punches, kicks, cape twirl, grapple rope, grapple gun, batarang + spinning batarang frames, smoke pellet,
  cape glide, crouch landing, brood). Native facing right. Pack scale 1.25 (2 device px per sprite px at 80 % on Retina).

### Batman (alternative, not used) — Justice League Task Force (Sega Genesis), via The Spriters Resource
- Downloaded 2026-10-11 → `ThirdParty/source-assets/genesis-batman/sheet.png` (1258×1196, `#008080` background).
- Fighting-game moves (bigger sprites, dizzy stars, cape spreads). Not mixed in: a different style from the SNES sheet.

## Considered / fallbacks

| Source | Notes | Verdict |
|---|---|---|
| [MCU Tribute Character Pack](https://everlywritesgames.itch.io/mcu-tribute-character-pack) (everlywritesgames, itch.io) | Free fan art. Top-down 16×16 (48×48 at 3×), 3-frame walk ×4 directions only. | Rejected as the main art: tiny, top-down, walk only. Could be a "mini mode" pet later. |
| [Marvel vs. Capcom: Infinite — Iron Man](https://www.spriters-resource.com/pc_computer/marvelvscapcominfinite/sheet/98622/) | HUD portraits only, no animation. | Not usable for animation. Possible settings-UI pet icon. |
| [UMvC3 — Iron Man victory portraits](https://www.spriters-resource.com/xbox_360/ultimatemarvelvscapcom3/sheet/42805/) | Static portraits. | Settings-UI icon at most. |
| [ScrollBoss custom Iron Man sprites](https://scrollboss.illmosis.net/customsprites.php?g=marvel&s=ironman-fgtsze) | Fan edits of Capcom sprites, mostly stances and win poses, alternate armors (Classic, Silver Centurion, Extremis). | Possible extra "armor skins" later. No fly or walk frames. |
| [Character Pixel Art Hero](https://moxica.itch.io/character-pixel-art-hero) (moxica, itch.io, from $3) | Original jetpack hero with flying and shooting animations. License allows personal and commercial use, no redistribution. | **Best licensed fallback** if the app is ever distributed ("Iron Man-inspired" original). |

## Future idea: Shimeji pack import
Shimeji / Shimeji-ee is a widely used desktop-pet format: a folder of `shime1.png…shime46.png` with fixed pose meanings (walk, climb wall, hang from ceiling, fall, sit, drag), plus `actions.xml`/`behaviors.xml`. Many fans have made character sets. An importer that maps Shimeji poses to our clips would unlock that whole catalogue. See [Shijima-Qt](https://pixelomer.itch.io/shijima), an open-source, Shimeji-ee-compatible app, for format reference. Candidate for post-M6.
