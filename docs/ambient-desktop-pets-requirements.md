# Ambient Desktop Pets — Product & Implementation Requirements

## 1. Product Vision

Build a macOS desktop-pet framework inspired by Clippy/Desktop Goose, but designed as a **non-intrusive ambient entertainment layer**.

The first pet will be an **Iron Man-inspired character**. The framework must eventually support multiple pets and reusable behavior/animation packs.

### Core principle

> **The pet is present, not intrusive.**

The user must be able to continue working normally while the pet appears, moves around, performs entertaining animations, and disappears.

The pet should feel like an occasional "cameo" rather than an assistant or notification.

---

## 2. Product Goals

### Primary goals

1. Support pets that appear occasionally on any connected display.
2. Allow pets to visually overlay normal applications.
3. Never block or interfere with the user's work.
4. Make pet windows click-through by default.
5. Support multi-monitor environments.
6. Provide random/probabilistic entertaining behavior.
7. Keep audio optional and disabled by default.
8. Make the framework extensible so new pets can be added without changing the core engine.
9. Allow pet-specific animation and behavior packs.
10. Support future context-aware behavior without coupling the framework to AI.

### Non-goals for V1

- No conversational AI assistant.
- No requirement for voice interaction.
- No arbitrary computer control.
- No pet actions that require the user to stop working.
- No mandatory user interaction.
- No intrusive notifications.

---

# 3. Core User Experience

The user is working normally in applications such as:

- VS Code
- Terminal
- Browser
- Photoshop
- Video editors
- Office applications
- Games
- Full-screen applications

After a randomized interval, a pet can appear.

Example:

```text
User is coding

        ┌──────────────────────────────────────┐
        │ VS Code                              │
        │                                      │
        │ function processData() {             │
        │     ...                              │
        │ }                                    │
        │                                      │
        │                          IRON MAN     │
        │                            🦾         │
        └──────────────────────────────────────┘

Iron Man walks in,
looks around,
performs an animation,
then leaves.

User continues typing the entire time.
```

The pet should never require the user to click it.

---

# 4. Interaction Model

## 4.1 Click-through behavior

Pet windows must normally be transparent to mouse input.

Desired behavior:

```text
Mouse
  |
  v
Pet visual layer
  |
  v
Mouse event passes through
  |
  v
Underlying application receives the click
```

If Iron Man is visually positioned above a Save button, clicking the Save button must still activate the Save button.

The pet should not steal focus.

---

## 4.2 Keyboard behavior

The pet must not:

- capture keyboard input
- steal application focus
- interrupt typing
- change the active application

The user should be able to continue typing normally.

---

## 4.3 Optional interaction mode

Future versions may support an explicit interaction mode.

For example:

- user intentionally clicks a pet
- pet becomes interactive temporarily
- normal click-through behavior is restored afterward

This should be opt-in rather than the default.

---

# 5. Multi-Monitor Support

The framework must support multiple connected displays.

Example:

```text
┌─────────────┐ ┌─────────────────┐ ┌─────────────┐
│             │ │                 │ │             │
│  Display 1  │ │    Mac Screen  │ │  Display 2  │
│             │ │                 │ │             │
└─────────────┘ └─────────────────┘ └─────────────┘
```

Each display should be treated as a potential pet playground.

The pet engine should be able to:

- select any connected display
- spawn a pet on a selected display
- move a pet between displays
- detect display resolution and visible bounds
- account for different display scaling
- handle display connect/disconnect events

### Cross-display scene

Example:

```text
Display 1:

Iron Man flies →
              \
               \
Display 2:      → Iron Man enters

                       \
                        \
Display 3:              → flies away
```

This should eventually be possible as a single animation scene.

---

# 6. Pet Window Requirements

Use a transparent, borderless floating window.

The window should ideally:

- have no title bar
- have transparent background
- stay above normal application windows when appropriate
- not appear in the Dock as a normal application window
- not appear as a normal document window
- avoid stealing focus
- allow mouse events to pass through
- support arbitrary positioning
- support animation
- support alpha/transparency
- support display-bound positioning

For macOS implementation, use **AppKit where low-level window behavior is required**. SwiftUI can be used for higher-level UI/settings.

---

# 7. Pet Engine Architecture

Recommended architecture:

```text
                         PET FRAMEWORK
                              |
             ┌────────────────┼────────────────┐
             |                |                |
        Screen Manager   Pet Scheduler    Context Manager
             |                |                |
             └────────────────┼────────────────┘
                              |
                         Behavior Engine
                              |
                    ┌─────────┴─────────┐
                    |                   |
              Scene Selector      Animation System
                    |                   |
                    └─────────┬─────────┘
                              |
                         Pet Renderer
                              |
                     Transparent Window
```

---

# 8. Main Components

## 8.1 Screen Manager

Responsibilities:

- enumerate displays
- track display bounds
- detect display changes
- identify usable screen regions
- expose display selection to the pet engine

Potential macOS APIs:

- NSScreen
- CGDisplay APIs where necessary

Example conceptual API:

```swift
protocol ScreenManager {
    func availableScreens() -> [PetScreen]
    func randomScreen() -> PetScreen
    func screen(with id: String) -> PetScreen?
}
```

---

## 8.2 Pet Scheduler

Controls when pets appear.

Do NOT make appearances completely random.

Use probabilistic scheduling.

Example:

```text
Minimum interval: 3 minutes
Maximum interval: 15 minutes

Event probabilities:

60% -> Quick cameo
25% -> Funny interaction
10% -> Elaborate scene
5%  -> Rare Easter egg
```

The scheduler should support:

- minimum interval
- maximum interval
- cooldown
- daily limits
- quiet hours
- full-screen suppression
- game suppression
- meeting suppression
- user-configurable frequency

---

# 9. Context Manager

The framework should eventually understand basic computer state without requiring AI.

Potential context:

```text
Active application
Active window
Keyboard activity
Mouse movement
Idle time
Full-screen status
Display configuration
```

Example states:

```text
ACTIVE_WORK
READING
IDLE
FULL_SCREEN
PRESENTATION
VIDEO_CALL
GAMING
```

These states influence pet behavior.

---

# 10. Context-Aware Behavior

### Active coding

Use:

```text
LOW FREQUENCY
SHORT CAMEOS
NO AUDIO
```

### Reading

Use:

```text
EDGE ANIMATIONS
SHORT CAMEOS
```

### Idle

Use:

```text
MORE FREQUENT
MORE INTERACTIVE
LONGER SCENES
```

### Full-screen presentation

```text
PAUSE PETS
```

### Video call / meeting

```text
PAUSE PETS
NO AUDIO
```

### Gaming

Default:

```text
PAUSE PETS
```

Allow users to override these policies.

---

# 11. Behavior Engine

The behavior engine decides what the pet should do.

Example:

```text
Behavior Engine
 |
 ├── Fly across screen
 ├── Walk
 ├── Run
 ├── Peek from edge
 ├── Look at cursor
 ├── Hide
 ├── Sit
 ├── Sleep
 ├── Fall
 ├── Dance
 ├── Inspect
 ├── Interact with another pet
 └── Leave
```

Behaviors should be composable.

Example:

```text
fly_in
  -> landing
  -> look_around
  -> repulsor
  -> salute
  -> takeoff
  -> fly_out
```

---

# 12. Scene System

Instead of only individual animations, define short "scenes".

A scene is a sequence of animations, timing, movement, and optional effects.

Example:

## Emergency Landing

```text
WAIT

WHOOSH

fly_in

landing

look_around

repulsor_effect

salute

takeoff

fly_out
```

Duration: approximately 8–20 seconds.

## Coffee Break

```text
walk_in
sit
drink_coffee
look_at_screen
stand
walk_out
```

## Code Review

```text
walk_in
look_at_user_screen
look_at_user
shake_head
walk_out
```

## Edge Peek

```text
peek_from_left
look_around
hide
```

## Cross-Monitor Flight

```text
screen_1.fly_in
screen_1.fly_to_edge
transition_to_screen_2
screen_2.fly_across
transition_to_screen_3
screen_3.fly_out
```

---

# 13. Avoiding Important UI

The framework should prefer areas that are less likely to interfere visually.

Priority:

1. screen edges
2. corners
3. unused/empty areas
4. title bars
5. areas outside the active application content
6. random safe areas

Avoid:

- text currently being read
- input fields
- important buttons
- active code region
- video controls
- presentation content

The pet remains click-through, but visual obstruction should still be minimized.

---

# 14. Pet Framework

The system should NOT hardcode Iron Man.

Instead define a generic pet contract.

Conceptual structure:

```text
Pet
 |
 ├── Identity
 ├── Visual Assets
 ├── Animations
 ├── Behaviors
 ├── Scenes
 ├── Sounds
 ├── Personality
 └── Configuration
```

Example:

```text
PetDefinition
    id
    name
    version
    assets
    animations
    scenes
    behaviors
    sounds
    personality
    constraints
```

---

# 15. Example Pet Packs

Initial:

```text
Iron Man
```

Future:

```text
Spider-Man
Deadpool
Cat
Dog
Robot
Alien
Ghost
Custom Pet
```

Behavior should be pet-specific.

### Iron Man

- fly
- land
- hover
- repulsor
- salute
- HUD scan
- helmet open/close

### Spider-Man

- swing
- climb
- stick to edge
- drop from top
- web animation

### Cat

- walk
- sleep
- stretch
- yawn
- chase cursor
- clean itself

### Ghost

- fade in
- float
- peek
- disappear

---

# 16. Animation System

Start with 2D animation for V1.

Possible formats:

- sprite sheets
- frame sequences
- vector animation
- skeletal 2D animation
- transparent video where appropriate

Recommended abstraction:

```swift
protocol PetAnimation {
    var id: String { get }
    var duration: TimeInterval { get }

    func play()
    func stop()
}
```

The renderer should not care whether the animation is sprite-based or another implementation.

---

# 17. V1 vs Future 3D

## V1

Use 2D.

Advantages:

- simpler implementation
- low CPU/GPU usage
- easier animation
- easier transparency
- faster iteration

## Future

Support 3D pets.

Potential pipeline:

```text
Blender
   |
   v
3D Model
   |
   v
Animations
   |
   v
Rendering Layer
   |
   v
Transparent macOS Window
```

3D should be a pluggable renderer rather than something deeply coupled to the core framework.

---

# 18. Iron Man Animation Library

Initial animation list:

```text
idle
walk
run
fly_in
fly_out
hover
landing
takeoff
look_left
look_right
look_at_cursor
repulsor
hud_scan
helmet_open
helmet_close
salute
dance
fall
sleep
confused
```

Scenes:

```text
Emergency Landing
Coffee Break
Code Review
Edge Peek
Fly Across Screen
Repulsor Test
HUD Scan
Random Walk
Sleep
Dance
```

Avoid using copyrighted assets directly in the framework prototype unless properly licensed.

For a distributable product, use original or properly licensed character designs/assets. An "Iron Man-inspired" prototype can use original art rather than Marvel-owned character assets.

---

# 19. Audio

Audio is optional.

Default:

```text
Visual: ON
Sound: OFF
Voice: OFF
```

Optional sounds:

- flying
- landing
- repulsor
- footsteps
- UI/HUD
- funny effects

Add global settings:

```text
Enable sounds
Volume
Only play sounds when user is idle
Never play during meetings
```

---

# 20. Future AI Integration

AI should be an optional layer, not a dependency of the core framework.

Architecture:

```text
              PET ENGINE
                  |
          ┌───────┴────────┐
          |                |
      Rule Engine      Optional AI
          |                |
          └───────┬────────┘
                  |
             Scene choice
```

AI can eventually decide:

```text
"What entertaining behavior would be appropriate right now?"
```

It can use context such as:

- active app
- time of day
- user idle/active state
- previous pet events
- pet personality
- frequency constraints

The AI must still operate inside the same safety and non-intrusion rules.

---

# 21. Personality System

Each pet can have a personality configuration.

Example:

```yaml
personality:
  friendliness: 0.8
  mischievousness: 0.6
  activity: 0.5
  interaction: 0.3
  verbosity: 0.1
```

Personality should influence scene selection.

For example:

```text
High mischievousness
    -> more surprise appearances

High friendliness
    -> more greetings/salutes

Low interaction
    -> mostly passive animations
```

---

# 22. Pet-to-Pet Interaction

Future feature.

Example:

```text
Iron Man appears
        |
        v
Spider-Man appears
        |
        v
They notice each other
        |
        v
Short interaction
        |
        v
Both leave
```

Possible scenes:

- chase
- fight
- greeting
- conversation
- race
- synchronized dance
- one pet scares another

These should remain visual and non-intrusive.

---

# 23. Settings

Provide a lightweight settings application/menu.

Recommended settings:

```text
General
-------
Enable pets                  [ON]

Frequency
---------
Minimum interval             [3 min]
Maximum interval             [15 min]

Behavior
--------
Quick cameos                 [ON]
Long scenes                  [ON]
Rare events                  [ON]

Interaction
-----------
React to cursor              [ON]
Cross-monitor scenes         [ON]

Audio
-----
Sounds                       [OFF]
Volume                       [50%]

Context
-------
Pause during full screen     [ON]
Pause during meetings        [ON]
Pause while gaming           [ON]

Performance
-----------
Maximum FPS                  [30]
Reduce animation quality     [OFF]
```

---

# 24. Quiet Hours

Allow users to define quiet periods.

Example:

```text
22:00 - 08:00
```

During quiet hours:

```text
No pets
No sounds
No animations
```

This prevents unexpected behavior at inappropriate times.

---

# 25. Performance Requirements

The pet must be lightweight.

Targets:

- low CPU usage while idle
- low GPU usage
- no noticeable impact on development tools
- minimal memory footprint
- animation capped at reasonable FPS
- stop rendering when pet is not visible
- pause unnecessary processing when the machine is under heavy load

The framework should avoid constantly polling at high frequency.

Prefer:

- timers
- event callbacks
- macOS notifications/events
- throttled context sampling

---

# 26. Safety / Non-Intrusion Rules

These are hard requirements.

The pet MUST NOT:

- steal focus
- capture keyboard input
- block mouse clicks
- prevent window movement
- interfere with typing
- force the user to interact
- interrupt full-screen presentations by default
- play audio unexpectedly by default
- open unwanted applications
- execute arbitrary shell commands
- modify user files
- interfere with system settings

The pet MAY:

- overlay visually
- move around
- react visually to cursor movement
- react to basic application context
- animate across displays
- display optional speech bubbles
- play optional sounds when enabled

---

# 27. Recommended Technology Stack

## macOS application

Primary:

```text
Swift
AppKit
SwiftUI
```

Use AppKit for:

- NSWindow
- window levels
- transparent windows
- event behavior
- display handling

Use SwiftUI for:

- settings
- configuration UI
- menus where convenient

## Animation

Start with:

```text
2D sprite/frame animation
```

Keep the renderer abstract so future implementations can support:

```text
SpriteRenderer
VectorRenderer
VideoRenderer
3DRenderer
```

## Data/configuration

Use JSON/YAML or Swift Codable structures.

Example:

```text
Pets/
  IronMan/
    pet.json
    animations/
    scenes/
    sounds/
```

---

# 28. Suggested Project Structure

```text
AmbientPets/
│
├── App/
│   ├── AmbientPetsApp.swift
│   └── AppLifecycle.swift
│
├── Core/
│   ├── PetEngine.swift
│   ├── PetScheduler.swift
│   ├── BehaviorEngine.swift
│   ├── SceneEngine.swift
│   └── PetRegistry.swift
│
├── Screen/
│   ├── ScreenManager.swift
│   ├── PetScreen.swift
│   └── ScreenRegionDetector.swift
│
├── Window/
│   ├── PetWindow.swift
│   ├── PetWindowController.swift
│   └── ClickThroughWindow.swift
│
├── Context/
│   ├── ContextManager.swift
│   ├── ActiveApplicationMonitor.swift
│   ├── IdleMonitor.swift
│   └── FullScreenDetector.swift
│
├── Rendering/
│   ├── PetRenderer.swift
│   ├── SpriteRenderer.swift
│   └── AnimationPlayer.swift
│
├── Models/
│   ├── PetDefinition.swift
│   ├── AnimationDefinition.swift
│   ├── SceneDefinition.swift
│   └── BehaviorDefinition.swift
│
├── Pets/
│   └── IronMan/
│       ├── pet.json
│       ├── animations/
│       ├── scenes/
│       └── sounds/
│
├── Settings/
│   ├── SettingsView.swift
│   └── SettingsStore.swift
│
└── Resources/
```

---

# 29. Pet Definition Example

Conceptual JSON:

```json
{
  "id": "ironman",
  "name": "Iron Man",
  "version": "0.1.0",
  "renderer": "2d",
  "animations": [
    "idle",
    "walk",
    "run",
    "fly_in",
    "fly_out",
    "landing",
    "takeoff",
    "hover",
    "repulsor",
    "salute",
    "look_at_cursor"
  ],
  "scenes": [
    "emergency_landing",
    "coffee_break",
    "code_review",
    "edge_peek",
    "cross_monitor_flight"
  ],
  "capabilities": {
    "cursor_tracking": true,
    "multi_monitor": true,
    "audio": true
  }
}
```

---

# 30. Scene Definition Example

Conceptual:

```json
{
  "id": "emergency_landing",
  "duration": 12,
  "steps": [
    {
      "animation": "fly_in",
      "duration": 3
    },
    {
      "animation": "landing",
      "duration": 2
    },
    {
      "animation": "look_around",
      "duration": 2
    },
    {
      "animation": "repulsor",
      "duration": 1
    },
    {
      "animation": "salute",
      "duration": 2
    },
    {
      "animation": "fly_out",
      "duration": 2
    }
  ]
}
```

---

# 31. Random Event Selection

Do not use pure random selection.

Use weighted selection plus constraints.

Example:

```text
Candidate scenes
        |
        v
Remove scenes blocked by context
        |
        v
Remove scenes in cooldown
        |
        v
Apply probability weights
        |
        v
Select scene
        |
        v
Select safe screen region
        |
        v
Play scene
```

Example:

```text
Current state: ACTIVE_WORK

Allowed:
  edge_peek              30%
  short_walk             25%
  fly_across             20%
  salute                 10%
  HUD_scan               10%
  rare_event              5%
```

---

# 32. Rare Events / Easter Eggs

The framework should support rare events.

Examples:

```text
Normal events:
  95%

Rare events:
   5%
```

Rare events may include:

- unusual animation
- multi-pet interaction
- special cross-monitor sequence
- very short surprise cameo

Frequency should be controlled independently so users don't see the same rare event repeatedly.

---

# 33. Event History

Maintain lightweight local history.

Example:

```text
lastScene
lastPet
lastScreen
lastAppearanceTime
sceneCounts
rareEventHistory
```

Purpose:

- avoid repetitive behavior
- enforce cooldowns
- balance scenes
- support rare events

No cloud storage is required for V1.

---

# 34. Development Roadmap

## Milestone 1 — Pet Window

Build:

- macOS app
- transparent window
- click-through
- borderless window
- always-on-top behavior
- manual pet positioning

Success criterion:

> A visual pet can appear over any application without interfering with work.

---

## Milestone 2 — Animation

Add:

- 2D animation
- animation player
- movement
- fade in/out
- basic Iron Man asset

Success criterion:

> Iron Man can enter, animate, and leave.

---

## Milestone 3 — Scheduler

Add:

- random intervals
- cooldowns
- weighted scenes
- display selection

Success criterion:

> Pet automatically makes occasional cameos.

---

## Milestone 4 — Multi-monitor

Add:

- screen discovery
- display selection
- movement across displays
- cross-display scenes

Success criterion:

> Pet can appear and travel across multiple displays.

---

## Milestone 5 — Context Awareness

Add:

- active application
- idle state
- full-screen detection
- meeting suppression
- gaming suppression

Success criterion:

> Pet adapts its frequency and behavior without interrupting work.

---

## Milestone 6 — Pet Framework

Add:

- PetDefinition
- PetRegistry
- pluggable animations
- pluggable scenes
- pet packs

Success criterion:

> A second pet can be added without changing the core engine.

---

## Milestone 7 — Pet-to-Pet

Add:

- multiple active pets
- interaction scenes
- coordinated animation

---

## Milestone 8 — Optional AI

Add:

- personality
- context-aware scene selection
- optional LLM integration
- generated conversational/speech content

AI must remain subordinate to the non-intrusive behavior rules.

---

# 35. Important Design Principle

The most important product decision is:

> **This is not an AI assistant disguised as a pet.**

It is an **ambient entertainment framework**.

The user should be able to forget it exists and work normally.

Then, occasionally:

```text
WHOOSH 💨

🦾

"Good work, sir."

WHOOSH 💨

Gone.
```

The user smiles and continues working.

That feeling is the product.

---

# 36. Future Product Direction

The framework can eventually become:

## Ambient Pets Platform

```text
                 Ambient Pets
                       |
          ┌────────────┼────────────┐
          |            |            |
        Pets         Scenes       Behaviors
          |            |            |
       Iron Man     Cameos        Walking
       Spider-Man   Stories       Flying
       Cat          Events        Dancing
       Robot        Easter Eggs   Interacting
          |
      Pet Marketplace
          |
     Custom Pet Packs
```

Potential future capabilities:

- downloadable pet packs
- custom user-created pets
- custom scenes
- pet editor
- animation editor
- behavior editor
- theme packs
- seasonal events
- multiple pets
- AI-generated behaviors
- community-created pet packs

---

# 37. First Implementation Recommendation

Do not build the complete framework initially.

Build this vertical slice first:

```text
macOS
  |
  v
Transparent click-through window
  |
  v
Simple 2D Iron Man
  |
  v
Fly-in animation
  |
  v
Walk/idle
  |
  v
Fly-out animation
  |
  v
Random 3–10 minute scheduler
  |
  v
Random connected display
```

Once this works reliably, build the framework around it.

This gives a working prototype quickly while validating the most important UX:

> **Can a pet entertain the user without interrupting their work?**
