# Manual QA

Re-run at every milestone exit. Use **Menu ▸ Summon ▸ Random Walk** (10 s) or `--summon all` unless a step says otherwise.
Turn on **Debug ▸ Outline Pet Window** to see the window's frame.

## Non-intrusion (M1, every milestone)

- [ ] Typing in TextEdit / VS Code continues uninterrupted while the pet shows (no lost keystrokes, caret keeps blinking).
- [ ] Clicking a button *under* the pet (inside the outline) activates the button.
- [ ] Frontmost app doesn't change. Debug builds log a fault `pet window changed the frontmost app` if it does:
      `log stream --predicate 'subsystem == "dev.jefflabs.AmbientPets"' --level debug`
- [ ] The pet is absent from Cmd-Tab, Cmd-\`, and Mission Control window thumbnails.
- [ ] Dragging a window beneath the pet works.
- [ ] Scrolling a page beneath the pet works.
- [ ] Over a full-screen app: with **Debug ▸ Allow Over Full-Screen Apps** on, a summoned pet appears over it.
- [ ] Switching Spaces mid-scene: the pet follows (`canJoinAllSpaces`) and focus stays put.

## Rendering (M2)

- [ ] Pixels are crisp (nearest-neighbour), no blur on Retina at 80 % and 100 % size.
- [ ] No jitter between poses (idle → walk → landing): feet stay planted.
- [ ] Facing: the pet faces its direction of travel; repulsor and beam fire in the facing direction.
- [ ] Thrusters come from the boots (hover: down; flight: backwards); dust puff + squash on landing.
- [ ] Speech bubble sits above the head, fully on screen, and moves with the pet.
- [ ] Pets talk only while standing / hovering, and stay put until a long line has been read (3–6 s); a line is
      never shown while the pet is off-screen, and the bubble leaves with the pet.
- [ ] Spider-Man ▸ Swing & Hang: animated web swing, flip, web shot, hangs upside down, zips up; head never past
      the top of the screen.
- [ ] Summon Together: Iron Man, Spider-Man and Batman look the same size.
- [ ] Spider-Man (`--summon spiderman`): Air Shot swings with the reach-up / curled swing pose and flips off the web;
      Edge Peek isn't cut; Dodge Roll zips up, swings and stays on screen (never below the ground); the Spider-Sense
      bubble doesn't bob with the rays; Stroll / Web Shot leave pulled up by the web (arm up, legs tucked); Wall
      Cling's sprint off stays on the ground.
- [ ] Iron Man (`--summon ironman`): Emergency Landing falls with braking jets straight to his spot and settles into
      the hover; Crash Landing tumbles, bounces (not cut off by the screen edge) and gets up; Rocket Punch dashes;
      Energy Shield bursts.
- [ ] Batman (`AmbientPets --summon batman` plays them all): Cape Glide never talks; Cape Spread / Night Patrol
      open the cape and take off without a pause; Grapple Drop and Rope Kick hang from the raised fist with moving
      legs; Training's moves run without freezes; walking has the same pace near or far from the edge.
- [ ] Edge Peek / Wall Cling on both screen edges: the whole bubble is on screen, its tail pointing at the head
      (`AMBIENT_PETS_ALWAYS_SPEAK=1 AmbientPets --summon spiderman/edge_peek` makes every line play).
- [ ] Feet land on the bottom of the visible frame (just above the Dock, or the screen bottom when the Dock hides).
- [ ] After a scene ends: no pet window remains, and CPU returns to ~0 % (`top -pid $(pgrep -x AmbientPets)`).

## Scheduler (M3)

- [ ] With default settings the menu shows "Next appearance in ~N min" and a cameo happens on its own.
- [ ] Pause for 1 Hour → no cameos; menu shows "Paused until …"; Resume restores the schedule.
- [ ] Quiet hours covering "now" → no cameos; the menu reports the gate.
- [ ] Disabling pets mid-scene ends the scene with a quick fade.
- [ ] Locking the screen mid-scene ends the scene; no cameo while locked; schedule resumes after unlock.
- [ ] Sleep / wake: no burst of cameos after wake.
- [ ] Changing the size slider affects the next scene.
- [ ] Launch at login toggles in Settings ▸ General (check System Settings ▸ General ▸ Login Items).

## Context awareness (M5)

Use **Debug ▸ Show Context Overlay** and `AmbientPets --context-probe` to see what the app detects.

- [ ] Join a Zoom / Meet / FaceTime call (mic on): the overlay shows VIDEO_CALL "microphone in use"; no cameos.
- [ ] Camera on, mic muted: still VIDEO_CALL ("camera in use").
- [ ] A scene that's playing when the call starts fades out within ~1 s.
- [ ] Keynote / PowerPoint slideshow full screen: PRESENTATION, no cameos.
- [ ] Any app in native full screen: FULL_SCREEN, no cameos (unless "Allow Over Full-Screen Apps").
- [ ] A game (App Store category Games, or listed in Settings ▸ Context): GAMING, no cameos.
- [ ] Reading a page in Safari / Preview without typing for 30 s: READING; cameos favour edges.
- [ ] With Accessibility granted, type in a long text field: pets never rest on the red caret box; moving the caret
      under a playing pet makes it leave early.
- [ ] Away from the keyboard for 2+ min: IDLE; cameos are more frequent and longer.
- [ ] Sounds on (Behavior ▸ Audio): sounds only when allowed (not while working, never in meetings, never in quiet hours).
- [ ] First launch shows the welcome / permissions window; "Grant…" opens the right System Settings pane.

## Pets together (M7)

- [ ] **Summon Together**: two (or three) pets, each in its own part of the screen, no overlap.
- [ ] **Summon Interaction ▸ Greeting / Race / Chase / Boo! / Dance-off**: the pets face each other at the right
      moments and wait for each other (nobody freezes; both leave).
- [ ] Pets ▸ Only One Pet: only that pet appears; Together is disabled.

## AI chooser (M8, optional)

- [ ] With no key, nothing changes. Settings ▸ AI: Provider OpenAI, paste the key, **Save to Keychain**, **Test**:
      a pick and a latency under 2 s (an "HTTP 404: model …" message means the model id needs changing).
- [ ] Turn on "Let AI pick scenes": cameos still respect every pause, quiet hours and limits.
- [ ] **Summon Now** with the AI on: the pet says a line about the situation (time, weekday, focus streak, being
      away); Settings ▸ AI shows the pick. Summon again: "not asked: same situation" and a normal line; the AI is
      asked again after the activity / part of day changes, every 45 min of focus, or after you come back. The first call after a rebuild may ask for Keychain access (Always Allow).
- [ ] Turn off the network: cameos continue (Settings ▸ AI shows "fell back").
- [ ] Settings ▸ AI ▸ Usage: Test adds one call (with tokens) and a Recent entry; a skipped cameo adds to
      "skipped"; the menu's "AI: N calls today" matches; Reset Counts clears it.
- [ ] **Test** sometimes returns `routine:<pet> [block, …]` and, the first time each day, moods (not shown in the
      menu). Next day the moods are asked for again.
- [ ] With 2+ pets out (Pets ▸ Mix, Together chance up): AI picks show `interaction:<id>` or `together` in
      Settings ▸ AI's last result, and the scene plays normally.
- [ ] `AmbientPets --summon routine:<pet>:<block>,<block>` for each pet: the routine enters, plays the blocks and
      leaves (block names in `Pets/<pet>/blocks.json`).
- [ ] Turning each AI toggle off removes that kind of pick.

## Multi-display (M4)

- [ ] Over many cameos, pets appear on every connected display.
- [ ] Monitor stacked above (or beside) the laptop: a pet entering or leaving through the shared edge never shows
      on the other display (no web line or feet poking through), and stays crisp on the Retina screen.
      `AMBIENT_PETS_DISPLAY=<n> AmbientPets --summon batman/grapple_drop` pins a summon to display n.
- [ ] Unplugging the display a pet is on ends the scene cleanly.
- [ ] **Summon ▸ Iron Man ▸ Cross-Monitor Flight** with two side-by-side displays: one continuous flight across both.
- [ ] Displays with a gap / offset arrangement: the pet fades out at one edge and fades in on the other display.
- [ ] Mixed Retina + non-Retina: sprites stay crisp on both while crossing.
