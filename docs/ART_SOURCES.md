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

### Black Panther, Captain America, Cosmic Ghost Rider, Hela, Thanos — Marvel Cosmic Invasion, via The Spriters Resource
- Same game, format and scale as Spider-Man and Iron Man: one PNG per frame on a 256×256 canvas, centre point (128, 224).
  Zips (in `ThirdParty/source-assets/OG/`): "Playable Characters - Black Panther / Captain America / Cosmic Ghost Rider"
  and "Bosses - Hela / Thanos". Credits in each folder's `Tag.txt`.
- Downloaded: ☑ 2026-10-16 → `ThirdParty/source-assets/cosmic-<id>/`:
  - `cosmic-blackpanther/default` (Default suit, 331 frames) + `effects/` (vibranium kunai, kinetic burst, claw streaks).
    Selectscreen = seated on the Wakandan throne.
  - `cosmic-captainamerica/merged` (Default suit, body + shield already composited) + `default/` (body and shield as
    separate layers; used for the thrown `Shield_*`, the Selectscreen salute and the shield-charge `Special`).
  - `cosmic-ghostrider/default` (Default suit, 397 frames) + `effects/` (pistol bolt, grenade, blue ground blast,
    flames). Special = rides his cosmic bike; Selectscreen = sitting on the bike.
  - `cosmic-hela/default` (231 frames) + `effects/` (necroswords, Fenrir, thorns, judgement orb; sub-folder names are
    prefixed, e.g. `Effects_FenrirActive_*`). No jump: she arrives and leaves as a cloud of crows (Dodge*).
  - `cosmic-thanos/default` (252 frames) + `effects/` (`Projectile_*` energy beam, `Drone_*`, `Turret_*`). Includes
    the finger snap, the Power Stone blast and the throne retreat.
  Colour variants in the zips are unused.
- In use: `petpack frames Pets/<id>/sprites/labels.json` with a fixed `"anchor": [128, 226]` (the game's own origin,
  feet on the ground) so flipping and pose changes never shift the character.

### Venom, Wolverine — Marvel Cosmic Invasion, via The Spriters Resource
- "Playable Characters - Venom / Wolverine" zips (in `ThirdParty/source-assets/OG/`), same format as the other Cosmic
  Invasion pets. Downloaded ☑ 2026-10-17 → `cosmic-venom/default` (Default suit, 450 frames; the zip's `Boss/` Venom
  and web pieces are kept in `boss/` and `effects/` but unused) and `cosmic-wolverine/default` (381 frames).
- Venom: Webswing (+ the engine's tether line), Attackair = giant fanged maw, Special = tendril storm,
  Selectscreen = symbiote roar. Wolverine: Selectscreen = claws out with "SNIKT", Specialfinisher = X-slash (512×512),
  Powergrabstart = the curled-up Fastball Special.
- In use: `petpack frames` with `"anchor": [128, 226], "canvas": [256, 256]`.

### The Flash, Superman — two sheets each, via The Spriters Resource
- **The Flash**: "Sega Genesis - Justice League Task Force - Fighters - Flash" (ripped by Apocalypse, `#008080`
  background) is the main sheet: fighting-stance idle, walk, somersault, lightning punches, bolt throw, arm-spin
  whirlwind, speed vortex, super-speed dash with speed lines, victory. The SNES version of the same game
  ("SNES - Justice League Task Force - Fighters - The Flash", ripped by HijodeKrypton, transparent) is packed in as
  `extra` (clips `s_*`): run cycle, vibrate/phase, rapid punches, backhand twister, crash and head rub.
- **Superman**: "SNES - Justice League Task Force - Fighters - Superman" (HijodeKrypton, transparent) is the main sheet:
  ground fighting, heat vision, freeze breath, cape flourish, the arms-up lift-off and the head-first dive. The Taito
  arcade game ("Arcade - Superman - Playable Characters - Superman", `#6292B1` background) is packed in as `extra`
  (clips `a_*`): Clark Kent walking and changing into Superman, walk cycle, idle, punches and kicks, energy charge and
  blast, the cape-flapping flight loop, fist-up take-off.
- Downloaded ☑ 2026-10-17 → `genesis-flash/`, `snes-flash/`, `snes-superman/`, `arcade-superman/` (each `sheet.png` +
  `work/` from `petpack slice`). The two sheets of each hero draw him within ~7 % of the same height, so no rescaling is
  applied; each scene sticks to one sheet so the art style never switches mid-scene.

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
