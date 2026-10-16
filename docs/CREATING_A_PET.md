# Creating a pet

A pet is a folder of data: no Swift. Drop it into `Pets/` (bundled) or
`~/Library/Application Support/AmbientPets/Pets/` (yours), then **Settings ▸ Pets ▸ Reload Packs**.

```
Pets/<id>/
  pet.json            identity, standing height, personality, capabilities, sounds
  sprites/sheet.png   packed frames (generated, gitignored for ripped art)
  sprites/atlas.json  frame rects + pivots (generated)
  sprites/labels.json which source frames make which clip (input to petpack)
  clips.json          animations built from atlas frames
  scenes/*.json       what the pet does
  lines.json          speech-bubble pools (optional)
  sounds/*.wav        short effects (optional)
  blocks.json         moves the AI may combine into new routines (optional)
```

Validate as you go: `petpack validate Pets/<id>` (or `make validate-packs`). The app skips invalid packs and shows
why in Settings ▸ Pets.

## 1. Get frames into a sheet

`P=$(swift build --package-path Packages/PetKit --show-bin-path)/petpack`

**One sheet with many sprites** (fighting-game rips):

```bash
$P slice source.png --out work --bg '#A34D4D' --merge 1 --min-pixels 40   # → work/contact.png, candidates.json
```

Open `work/contact.png`, note the numbered frames you want, and write `sprites/labels.json`:

```json
{ "slice": { "bg": "#A34D4D", "merge": 1, "minPixels": 40 },
  "pivot": "torso",
  "pivotByClip": { "batarang": "center", "beam": "left" },
  "flip": [402, 403],
  "clips": { "idle": [0, 1, 2, 3], "walk": [7, 8, 9, 10, 11, 12], "batarang": [49, 51, 52, 53] } }
```

```bash
$P pack work/candidates.json Pets/<id>/sprites/labels.json --out Pets/<id>/sprites --facing right
```

**One PNG per frame on a shared canvas** (Cosmic Invasion style):

```json
{ "dir": "ThirdParty/source-assets/<source>/default", "facing": "right", "anchorFrom": "Idle_00.png",
  "pivotByClip": { "web_ball": "center", "beam": "left" },
  "clips": { "idle": ["Idle_*"], "sense": ["Idle_00.png+Spidersense_*"], "web_ball": ["../effects/Shot_*"] } }
```

```bash
$P frames Pets/<id>/sprites/labels.json --out Pets/<id>/sprites
```

`Name_*` expands in frame order (`_02-03` and `_04_08_12` style repeats are honoured); `A+B` composites B over A;
empty frames are kept as pauses. Every frame keeps the canvas anchor as its pivot, so poses never jitter.
Rips that centre oversized frames on a base canvas (Cosmic Invasion: a 512×256 attack has 128 px extra each side) need
`"anchor": [128, 226], "canvas": [256, 256]`: frames bigger than `canvas` get their anchor moved by half the extra
size, so wide attacks, tall rainbow entrances and 512×512 boss moves stay on the feet.

Pivot modes: `feet` (default: bottom-centre of the feet), `torso` (chest centre, feet height: steadier walks),
`center` (projectiles, effects), `left` (beams anchored at the muzzle). Override single frames with `"pivots"`.

Check alignment and timing with `$P preview Pets/<id> walk --out walk.png` (frames side by side) or `.gif`.

## 2. pet.json

```json
{ "formatVersion": 1, "id": "batman", "name": "Batman", "version": "0.1.0", "renderer": "sprite",
  "height": 90,
  "personality": { "activity": 0.9, "friendliness": 0.3, "mischievousness": 0.5, "interaction": 0.4, "curiosity": 0.7 },
  "capabilities": { "canWalk": true, "canGlide": true, "canGrapple": true },
  "sounds": { "thud": "sounds/thud.wav" } }
```

- `height`: standing height in sprite px. Every pet renders at the same on-screen height (135 pt at 100 %), so pets
  from different games match. Measure the idle pose, then adjust by eye next to the other pets (`summon together`):
  a slim or crouching character may need a smaller value to *look* the same size as a bulky one.
- Personality: `activity` scales frequency; the others weight scene tags (`friendliness` → `greeting`,
  `mischievousness` → `surprise`, `interaction` → `cursor`, `curiosity` → `explore` / `scan`).
- Capabilities are free-form; scenes can require them (`"requires": { "capabilities": ["canSwing"] }`).

## 3. clips.json

```json
{ "formatVersion": 1, "clips": {
  "idle":  { "frames": ["idle_0", "idle_1"], "fps": 8, "points": { "head": [-2, 95] } },
  "fly":   { "frames": ["fly_0"], "fps": 1, "lean": 12, "thrustDirection": "down", "points": { "thruster": [0, 1] } },
  "shoot": { "frames": ["shoot_0", "shoot_1"], "fps": 12, "loop": false, "points": { "hand": [70, 78] } },
  "look":  { "fallback": "idle" } } }
```

- `points`: named attachment points (px from the pivot, y up, in the art's native facing) used by effects:
  `hand`, `chest`, `muzzle`, `head`, `web`, `thruster`, `feet`. Use `petpack preview` and measure.
- `fallback`: scenes can ask for clips the sheet doesn't have (`look`, `sleep`…).
- `lean`: body tilt in degrees while the clip plays. `mirrorForLeft: false` for art with its own left frames.

## 4. Scenes

```json
{ "id": "batarang", "name": "Batarang", "tier": "funny", "weight": 1, "tags": ["flashy"], "cooldownMinutes": 20,
  "region": "bottom_edge", "allowedContexts": ["IDLE", "ACTIVE_WORK"],
  "steps": [
    { "clip": "walk", "duration": 2.0, "motion": { "type": "moveTo", "from": "side_offscreen", "to": "anchor" } },
    { "clip": "throw", "duration": 1.0, "facing": "toward_center", "sound": "swish",
      "effects": [{ "type": "projectile", "clip": "batarang", "at": "hand", "speed": 560, "distance": 300 }],
      "speech": { "pool": "throw", "chance": 0.25 } },
    { "clip": "walk", "duration": 2.2, "motion": { "type": "exit", "to": "opposite_offscreen" } } ] }
```

Total 3–30 s. Tiers roll 60 / 25 / 10 / 5 % (quick / funny / elaborate / rare); rare scenes play at most every 48 h.

**Regions** (where the anchor is): `bottom_edge`, `side_edge`, `top_edge`, `air`, `anywhere`.

**Anchor refs** for `from` / `to`: `anchor`, `current`, `ground`, `center`, `screen_center`, `top_offscreen`,
`bottom_offscreen`, `left_offscreen`, `right_offscreen`, `side_offscreen` (the entry side), `opposite_offscreen`,
`wall`, `wall_below`, `wall_high` (on the `side` edge). `offset: [dx, dy]` nudges the target; `advance: [dx, dy]`
moves relative to the current point along the heading.

**Motions**: `none`, `enter`, `exit`, `moveTo`, `walk` (speed / distance / direction), `hover` (amplitude /
frequency), `hop` (height), `drop`, `arc` (height), `swing` (pendulum on a line; `attach: "top"`, `sweep`),
`cling` (crawl along a side edge, rotated), `cross_display` (fly onto the next display). `curve`: `linear`,
`easeIn`, `easeOut`, `easeInOut`.

**Facing** per step: automatic (direction of travel), `left`, `right`, `toward_center`, `away_from_center`,
`keep`, `cursor`. Standing / hovering steps without a rule turn to face the pointer (setting "React to cursor").

**Effects**: `thruster`, `dust_puff`, `squash`, `tilt`, `fade` (`mode: in|out`), `repulsor_flash`, `beam`,
`scanline`, `zzz`, `speech_bubble`, `tether_line` (web / grapple line; to the screen top, to a swing's anchor, or a
fixed `length` with `angle`), `projectile` (`clip`, `hit`, `speed`, `distance`, `rise`, `delay`), `overlay`
(`clip` attached at a point, e.g. a beam from `muzzle`; `hold: false` hides it when done).

**Speech**: `"speech": { "pool": "<lines.json pool>", "chance": 0.3 }` on a step. Pets talk only while standing,
hovering or clinging in place: a line on a moving step waits for the next still step (and is dropped if the pet
never stops, e.g. a glide across the screen), and the pet stays there until the line has been read. Put speech on a
still step.

**Smooth timing**: a non-looping clip lasts `frames / fps` seconds. If a standing step is longer, the pet freezes
on the last frame, which reads as a pause; `petpack validate` warns about it. Match the step to the clip, or lower
the clip's `fps`. For walking in or out, give the move a pace instead of a fixed time:
`"motion": { "type": "exit", "to": "side_offscreen", "speed": 85 }` (native px/s); the step then lasts as long as
the distance takes, so the legs match the ground however far the edge is.

**Sounds**: `"sound": "<name>"` from `pet.json`. Off unless the user enables sounds; never while working, in
meetings, or during quiet hours.

## 5. Together scenes (optional)

Shared scenes for two pets live in `Pets/_ensembles/*.json` (see the files there). Each role lists required
capabilities and its own steps on a shared timeline; `"waitFor": "b:2"` holds a step until role `b` reaches step 2,
and `"facing": "partner"` turns towards the other pet. Use the common clip ids every pet defines (`idle`, `walk`,
`celebrate`, `surprised`, `attack`) and add fallbacks in `clips.json` for any your pet lacks.

## 6. Routine blocks (optional, for the AI)

`blocks.json` lists short, self-contained moves. With AI routines on, the AI picks 2–5 of them and the app plays
`enter` + blocks + `exit` as a new bottom-edge scene (trimmed to 30 s). Each block should start and end standing on
the ground so any order works.

```json
{ "enter": [{ "clip": "walk", "duration": 2.0, "motion": { "type": "moveTo", "from": "side_offscreen", "to": "anchor" } }],
  "exit":  [{ "clip": "walk", "duration": 2.0, "motion": { "type": "exit", "to": "opposite_offscreen" } }],
  "blocks": {
    "batarang": { "description": "throws a batarang", "steps": [
      { "clip": "throw", "duration": 1.0, "facing": "toward_center",
        "effects": [{ "type": "projectile", "clip": "batarang", "at": "hand", "speed": 560, "distance": 300 }] }] },
    "brood": { "description": "stands still, cape drawn, staring", "steps": [{ "clip": "idle", "duration": 2.0 }] } } }
```

The `description` is what the AI sees, so keep it short and concrete. `petpack validate` checks clips, effects and
sounds, and that there are at least two blocks. Try one: `AmbientPets --summon routine:<id>:brood,batarang`.

## 7. Checklist

- [ ] `petpack validate` passes
- [ ] `petpack preview` strips look aligned (no jitter between poses)
- [ ] every scene plays: `AmbientPets --summon <id>` (add `AMBIENT_PETS_SNAPSHOT_DIR=/tmp/s` to get PNGs per step)
- [ ] facing is right both ways; effects come from the right points
- [ ] art licence noted in `docs/ART_SOURCES.md`; ripped art stays gitignored
