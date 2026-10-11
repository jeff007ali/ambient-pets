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
- [ ] Speech bubble sits above the head, inside the window, and disappears after ~2.6 s.
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
- [ ] Turn off the network: cameos continue (Settings ▸ AI shows "fell back").
- [ ] **Test** sometimes returns `routine:<pet> [block, …]` and, the first time each day, moods; the menu then shows
      "Moods: …". Next day the moods are asked for again.
- [ ] With 2+ pets out (Pets ▸ Mix, Together chance up): AI picks show `interaction:<id>` or `together` in
      Settings ▸ AI's last result, and the scene plays normally.
- [ ] `AmbientPets --summon routine:<pet>:<block>,<block>` for each pet: the routine enters, plays the blocks and
      leaves (block names in `Pets/<pet>/blocks.json`).
- [ ] Turning each AI toggle off removes that kind of pick.

## Multi-display (M4)

- [ ] Over many cameos, pets appear on every connected display.
- [ ] Unplugging the display a pet is on ends the scene cleanly.
- [ ] **Summon ▸ Iron Man ▸ Cross-Monitor Flight** with two side-by-side displays: one continuous flight across both.
- [ ] Displays with a gap / offset arrangement: the pet fades out at one edge and fades in on the other display.
- [ ] Mixed Retina + non-Retina: sprites stay crisp on both while crossing.
