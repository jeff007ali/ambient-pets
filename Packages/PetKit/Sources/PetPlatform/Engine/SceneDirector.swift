import AppKit
import PetCore
import PetImaging
import QuartzCore

/// Runs one scene: plans the anchor, creates the window, drives a display link through the steps, and tears
/// everything down (window closed, display link invalidated) when it ends, however it ends.
@MainActor
public final class SceneDirector: NSObject {
    public struct Options {
        /// User size slider (0.5…1.5). Multiplied by the pack's `defaultScale`.
        public var userScale = 0.8
        public var maxFPS = 30
        public var speechBubbles = true
        public var reduceQuality = false
        public var outlineWindow = false
        /// Turn to face the mouse pointer while standing or hovering.
        public var reactToCursor = true
        /// AI-generated line: always shown, on the first step that speaks (or the first step after the entrance).
        public var speechOverride: String?
        public init() {}
    }

    public enum Outcome: Sendable {
        case completed
        case aborted(String)
    }

    /// Result of the once-a-second safety check while a scene plays.
    public enum SafetyAction: Sendable {
        case ok
        /// Something moved into the pet's way (the caret): skip to the exit step.
        case exitEarly
        /// The context no longer allows pets (meeting, full screen, lock…): fade out now.
        case abort(String)
    }

    /// Called about once a second with the pet window's frame (AppKit global).
    public var safetyCheck: ((CGRect) -> SafetyAction)?
    /// Called when a step with a `sound` starts.
    public var playSound: ((LoadedPack, String) -> Void)?
    /// Ensembles: is a step's `waitFor` ("b:2") satisfied yet?
    public var waitGate: ((String) -> Bool)?
    /// Ensembles: where the partner is (for `"facing": "partner"`).
    public var partnerPosition: (() -> CGPoint?)?
    /// The pet's feet, AppKit global.
    public var pivotPosition: CGPoint { position }
    /// 1-based number of the step playing (or held) now; 0 before the start.
    public var currentStepNumber: Int { stepIndex + 1 }
    private var holding = false
    /// True when every candidate spot hit a blocking obstacle: don't start this scene.
    public private(set) var isBlocked = false
    /// Debug overlay: anchors the planner tried.
    public private(set) var planCandidates: [CGPoint] = []
    public var anchor: CGPoint { plan.anchor }
    private var sinceSafetyCheck = 0.0
    private var exitingEarly = false

    public let pack: LoadedPack
    public let scene: SceneDefinition
    public let display: DisplayGeometry
    private var options: Options
    private let rng: RandomSource
    private var onFinish: ((Outcome) -> Void)?

    private let scale: Double
    private var plan: ScenePlan
    private var window: PetWindowController?
    private var renderer: SpriteRenderer?
    private var link: CADisplayLink?
    private var watchdog: Timer?

    private var stepIndex = -1
    private var stepElapsed = 0.0
    private var track: MotionTrack
    private var position: CGPoint
    private var effects: [EffectInstance] = []
    private var bubble: SpeechBubble?
    /// A line waiting until the pet is on screen and standing still (it may still be entering or moving).
    private var pendingLine: String?
    /// Extra time the current step lasts so its line can be read.
    private var speechHold = 0.0

    /// Standing, hovering or clinging in place: a moment the pet can talk.
    static func isStill(_ step: StepDefinition) -> Bool {
        switch step.motion.type {
        case .none, .hover: return true
        case .cling: return step.motion.to == "current"
        default: return false
        }
    }
    /// The step that shows `Options.speechOverride`.
    private let aiSpeechStep: Int
    private var lastTimestamp: CFTimeInterval = 0
    private var abortRemaining: Double?
    private var abortReason = ""
    private var tickCount = 0
    private var startTime: CFTimeInterval = 0
    private static let debugStats = ProcessInfo.processInfo.environment["AMBIENT_PETS_DEBUG"] != nil
    /// Debug: render the layer tree to `<dir>/<scene>_<step>.png` shortly after each step starts.
    /// Dev: `AMBIENT_PETS_TRACE=1` logs the pet's position (every 3rd frame) and each line it says to stderr.
    private static let trace = ProcessInfo.processInfo.environment["AMBIENT_PETS_TRACE"] != nil
    /// Dev: `AMBIENT_PETS_ALWAYS_SPEAK=1` makes every speech line play (QA for bubbles).
    private static let alwaysSpeak = ProcessInfo.processInfo.environment["AMBIENT_PETS_ALWAYS_SPEAK"] != nil
    private static let snapshotDir = ProcessInfo.processInfo.environment["AMBIENT_PETS_SNAPSHOT_DIR"].map(URL.init(fileURLWithPath:))
    private var snapshotPending = false
    /// Debug: with `AMBIENT_PETS_SNAPSHOT_EVERY=<seconds>`, also snapshot on that interval (frame sequences).
    private static let snapshotEvery = ProcessInfo.processInfo.environment["AMBIENT_PETS_SNAPSHOT_EVERY"].flatMap(Double.init)
    private var sinceSnapshot = 0.0
    private var sequenceIndex = 0

    public private(set) var isRunning = false
    public private(set) var hasStarted = false
    private var cancelledBeforeStart: String?

    public init(pack: LoadedPack, scene: SceneDefinition, display: DisplayGeometry, options: Options,
                rng: RandomSource, lane: ScreenLane? = nil, obstacles: [Obstacle] = [], allDisplays: [DisplayGeometry] = [],
                placement: (anchor: CGPoint, side: HorizontalSide)? = nil, onFinish: @escaping (Outcome) -> Void) {
        self.pack = pack
        self.scene = scene
        self.display = display
        self.options = options
        self.rng = rng
        self.onFinish = onFinish
        scale = pack.data.definition.renderScale(userScale: options.userScale)
        let box = Self.box(for: scene, pack: pack, scale: scale, display: display)
        // The AI's line goes on the first standing / hovering step after the entrance.
        aiSpeechStep = scene.steps.indices.first { i in Self.isStill(scene.steps[i]) && (i > 0 || scene.steps.count == 1) }
            ?? (scene.steps.count > 1 ? 1 : 0)
        if let placement {
            plan = ScenePlan(display: display, box: box, anchor: placement.anchor, side: placement.side)
            planCandidates = [placement.anchor]
        } else if let safe = SafeRegionPlanner.plan(region: scene.region, display: display, box: box, rng: rng, lane: lane,
                                                    obstacles: obstacles, headroom: Self.headroom(scene, scale: scale)) {
            plan = safe.plan
            planCandidates = safe.candidates
        } else {
            plan = ScenePlanner.plan(region: scene.region, display: display, box: box, rng: rng, lane: lane,
                                     headroom: Self.headroom(scene, scale: scale))
            isBlocked = true
        }
        plan.allDisplays = allDisplays.isEmpty ? [display] : allDisplays
        position = plan.anchor
        track = MotionTrack(type: .none, start: plan.anchor, end: plan.anchor, duration: 0, curve: .linear)
    }

    /// How far the scene lifts the pet above its anchor at most (arcs and hops peak at `height`, hovers bob).
    static func headroom(_ scene: SceneDefinition, scale: Double) -> Double {
        scene.steps.map { step in
            let m = step.motion
            switch m.type {
            case .arc: return (m.height ?? 60) * scale
            case .hop: return (m.height ?? 20) * scale
            case .hover: return (m.amplitude ?? 5) * scale
            default: return 0
            }
        }.max() ?? 0
    }

    /// Window size: the union of all frames the scene uses, plus room for its effects.
    static func box(for scene: SceneDefinition, pack: LoadedPack, scale: Double, display: DisplayGeometry) -> PetBox {
        let displayHeight = display.frame.height
        let extents = pack.extents(for: scene)
        let effects = scene.steps.flatMap(\.effects)
        let has = { (t: EffectType) in effects.contains { $0.type == t } }
        let reach = extents.mirrorSafe.scaled(scale).right
        var side = 24.0
        var top = 0.0
        if let beam = effects.first(where: { $0.type == .beam }) {
            side = max(side, (beam.double("length") ?? 150) * scale - reach + 24)
        }
        if has(.thruster) { side = max(side, 56 * scale) }
        // Overlays (beams, shockwaves) extend from a body point; fit the widest / tallest frame around the pet.
        for fx in effects where fx.type == .overlay {
            let frames = fx.string("clip").flatMap { pack.data.clips.resolveOrDefault($0)?.frames } ?? []
            for name in frames {
                guard let f = pack.geometry[name] else { continue }
                let ext = f.extents.scaled(scale)
                side = max(side, max(ext.left, ext.right) + reach * 0.6 - reach + 16)
                top = max(top, ext.up + 16)
            }
        }
        // Swings: the line's anchor is up to `radius` above and `radius·sin(sweep/2)` to the side of the feet.
        for step in scene.steps where step.motion.type == .swing {
            let half = (step.motion.sweep ?? 100) / 2 * .pi / 180
            var r = (step.motion.radius ?? 220) * scale
            if step.motion.attach == "top" {
                // Worst case: the lowest point the planner may start this region from, up to the screen's top edge.
                let v = display.visibleFrame
                let lowest = scene.region == .air ? v.minY + v.height * 0.45 : v.minY
                r = (display.frame.maxY - lowest) / cos(half)
            }
            side = max(side, r * sin(half) - reach + 16)
            top = max(top, r + 16)
        }
        // Projectiles fly forward from the pet; the window must contain the whole flight (both facings).
        for fx in effects where fx.type == .projectile {
            let hitSize = fx.string("hit").flatMap { pack.data.clips.resolveOrDefault($0)?.frames }
                .flatMap { $0.compactMap { pack.geometry[$0]?.rect.width }.max() } ?? 0
            side = max(side, ((fx.double("distance") ?? 240) + hitSize / 2 + 16) * scale - reach + 8)
        }
        let bottom: Double = (has(.thruster) || has(.dustPuff)) ? 56 * scale + 8 : 12
        top = max(top, 12 + (has(.zzz) ? 36 : 0))
        // An unbounded web line must reach past the top of the screen from anywhere on it.
        // (In a swing step the line runs to the swing's anchor instead, covered above.)
        let unbounded = scene.steps.contains { step in
            step.motion.type != .swing && step.effects.contains { $0.type == .tetherLine && $0.double("length") == nil }
        }
        if unbounded { top = max(top, displayHeight + 24) }
        if let swing = effects.first(where: { $0.type == .tetherLine && $0.double("length") != nil }) {
            top = max(top, (swing.double("length") ?? 0) * scale + 12)
            side = max(side, (swing.double("length") ?? 0) * scale * sin((swing.double("angle") ?? 0) * .pi / 180) - reach + 12)
        }
        // Speech bubbles have their own window, so they need no room here.
        return PetBox.make(extents: extents, scale: scale, padding: .init(side: side, top: top, bottom: bottom))
    }

    public func start() {
        guard !hasStarted else { return }
        hasStarted = true
        if let reason = cancelledBeforeStart { finish(.aborted(reason)); return }
        guard !scene.steps.isEmpty else { finish(.aborted("empty scene")); return }
        isRunning = true
        let window = PetWindowController(size: plan.box.size, outline: options.outlineWindow)
        let renderer = SpriteRenderer(pack: pack, scale: scale, pivot: plan.box.pivot, in: window.rootLayer)
        renderer.facing = plan.anchor.x < display.visibleFrame.midX ? .right : .left
        self.window = window
        self.renderer = renderer

        beginStep(0)
        window.updateContentsScale()
        place()
        window.show()

        // Tick from the scene's *display*, not the view: a view's link pauses while its window is fully off-screen,
        // which is exactly where most scenes start.
        let screen = NSScreen.screens.first { ScreenManager.geometry(of: $0).id == display.id } ?? NSScreen.main
        guard let link = screen?.displayLink(target: self, selector: #selector(tick(_:))) else {
            finish(.aborted("no display link"))
            return
        }
        let fps = Float(max(options.maxFPS, 10))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: min(15, fps), maximum: fps, preferred: fps)
        link.add(to: .main, forMode: .common)
        self.link = link
        lastTimestamp = CACurrentMediaTime()
        startTime = lastTimestamp

        // Guaranteed teardown even if the display link stalls (e.g. the display sleeps). Ensembles may wait on a
        // partner, so they get extra slack.
        // Speech holds add up to a few seconds.
        let slack = (scene.steps.contains { $0.waitFor != nil } ? 20.0 : 5.0) + 8
        let watchdog = Timer(timeInterval: scene.totalDuration + slack, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish(.aborted("watchdog")) }
        }
        RunLoop.main.add(watchdog, forMode: .common)
        self.watchdog = watchdog
    }

    /// Ends the scene early with a quick fade (display unplugged, screen locked, user paused).
    public func abort(_ reason: String) {
        // Queued but not started yet (staggered group): it ends as soon as it would start.
        if !hasStarted { cancelledBeforeStart = reason; return }
        guard isRunning, abortRemaining == nil else { return }
        abortReason = reason
        abortRemaining = 0.25
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = window?.rootLayer.presentation()?.opacity ?? 1
        fade.toValue = 0
        fade.duration = 0.25
        window?.rootLayer.opacity = 0
        window?.rootLayer.add(fade, forKey: "abort")
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        tickCount += 1
        let dt = min(max(now - lastTimestamp, 0), 0.1)
        lastTimestamp = now

        if let remaining = abortRemaining {
            abortRemaining = remaining - dt
            if remaining - dt <= 0 { finish(.aborted(abortReason)) }
            return
        }

        if let check = safetyCheck {
            sinceSafetyCheck += dt
            if sinceSafetyCheck >= 1, let frame = window?.panel.frame {
                sinceSafetyCheck = 0
                switch check(frame) {
                case .ok: break
                case .exitEarly: exitEarly()
                case .abort(let why): abort(why); return
                }
            }
        }

        if holding {
            // Waiting on a partner: the pose animates, the step itself hasn't started.
            if let w = scene.steps[stepIndex].waitFor, !(waitGate?(w) ?? true) {
                renderer?.advance(by: dt)
                faceStep(scene.steps[stepIndex])
                place()
                return
            }
            holding = false
            startStepContent(scene.steps[stepIndex])
        }

        stepElapsed += dt
        while stepElapsed >= scene.steps[stepIndex].duration + speechHold {
            stepElapsed -= scene.steps[stepIndex].duration + speechHold
            position = track.position(at: track.duration)
            endStep()
            guard stepIndex + 1 < scene.steps.count else {
                place()
                finish(.completed)
                return
            }
            beginStep(stepIndex + 1)
        }
        position = track.position(at: stepElapsed)
        if Self.trace, tickCount % 3 == 0 {
            FileHandle.standardError.write(Data(String(format: "trace step=%d t=%.2f x=%.0f y=%.0f\n", stepIndex, stepElapsed, position.x, position.y).utf8))
        }
        renderer?.setSwing(track.rotates ? track.rotation(at: stepElapsed) : nil, dt: dt)
        followCursor(dt)
        if track.hop != nil { window?.rootLayer.opacity = Float(track.opacity(at: stepElapsed)) }
        else if let root = window?.rootLayer, root.opacity < 1, abortRemaining == nil, root.animation(forKey: "fade") == nil { root.opacity = 1 }
        renderer?.advance(by: dt)
        for fx in effects { fx.update(dt: dt) }
        place()
        speakIfVisible()
        if let b = bubble, let renderer {
            if b.isClosed { bubble = nil } else { b.follow(head: globalHead(renderer)) }
        }
        if snapshotPending, stepElapsed > 0.25 { snapshot() }
        if let every = Self.snapshotEvery {
            sinceSnapshot += dt
            if sinceSnapshot >= every {
                sinceSnapshot = 0
                sequenceIndex += 1
                snapshot(name: String(format: "%@_seq%03d", scene.id, sequenceIndex))
            }
        }
    }

    private func snapshot(name: String? = nil) {
        if name == nil { snapshotPending = false }
        guard let dir = Self.snapshotDir, let root = window?.rootLayer else { return }
        let size = plan.box.size, s = 2.0
        guard let ctx = CGContext(data: nil, width: Int(size.width * s), height: Int(size.height * s), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.setFillColor(CGColor(gray: 0.9, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: size.width * s, height: size.height * s))
        ctx.scaleBy(x: s, y: s)
        root.render(in: ctx)
        guard let image = ctx.makeImage() else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? ImageFiles.writePNG(image, to: dir.appending(path: "\(name ?? "\(scene.id)_\(stepIndex + 1)").png"))
    }

    private func beginStep(_ i: Int) {
        guard let renderer else { return }
        stepIndex = i
        speechHold = 0
        snapshotPending = Self.snapshotDir != nil
        let step = scene.steps[i]
        // An explicit facing rule decides the heading used by `advance` and `swing`; "auto" keeps the current one.
        let still = MotionTrack(type: .none, start: position, end: position, duration: 0, curve: .linear)
        let heading = step.facing.map { _ in MotionTrack.facing(rule: step.facing, track: still, current: renderer.facing, plan: plan) } ?? renderer.facing
        track = MotionTrack.make(spec: step.motion, duration: step.duration, current: position, plan: plan, scale: scale,
                                 rng: rng, heading: heading)
        position = track.position(at: 0)
        renderer.facing = MotionTrack.facing(rule: step.facing, track: track, current: renderer.facing, plan: plan)
        faceStep(step)
        if let clip = pack.data.clips.resolveOrDefault(step.clip) { renderer.play(clip) }
        if let w = step.waitFor, !(waitGate?(w) ?? true) {
            // Hold at the start of this step until the partner gets there.
            holding = true
            stepElapsed = 0
            return
        }
        startStepContent(step)
    }

    private func faceStep(_ step: StepDefinition) {
        guard step.facing == "partner", let renderer, let p = partnerPosition?(), abs(p.x - position.x) > 4 else { return }
        renderer.facing = p.x > position.x ? .right : .left
    }

    /// Effects, speech and sound for a step (deferred while holding for a partner).
    private func startStepContent(_ step: StepDefinition) {
        guard let renderer else { return }
        if let sound = step.sound { playSound?(pack, sound) }

        var ctx = EffectContext(renderer: renderer, stepDuration: step.duration, reduceQuality: options.reduceQuality,
                                windowTopAbovePivot: plan.box.size.height - plan.box.pivot.y)
        ctx.swingRadius = track.pendulum?.radius
        effects = step.effects.compactMap { EffectFactory.make($0, ctx) }

        var line: String?
        if options.speechBubbles, let speech = step.speech, Self.alwaysSpeak || rng.chance(speech.chance ?? 1) {
            line = speech.text ?? speech.pool.flatMap { rng.element(of: pack.data.lines[$0] ?? []) }
        }
        if options.speechBubbles, let fx = step.effects.first(where: { $0.type == .speechBubble }) {
            line = fx.string("text") ?? fx.string("pool").flatMap { rng.element(of: pack.data.lines[$0] ?? []) } ?? line
        }
        // The AI's line about the user's situation wins, and doesn't depend on the authored chance roll.
        if options.speechBubbles, stepIndex == aiSpeechStep, let override = options.speechOverride {
            line = override
            options.speechOverride = nil
        }
        if let line, window != nil { pendingLine = line }
        speakIfVisible()
    }

    private var sinceCursorLook = 0.0

    /// While standing or hovering (no explicit facing in the step), face the mouse pointer. Reads the pointer
    /// position directly: no event monitor, no permission.
    private func followCursor(_ dt: Double) {
        guard options.reactToCursor, let renderer, !track.rotates, track.type == .none || track.type == .hover else { return }
        let rule = scene.steps[stepIndex].facing
        guard rule == nil || rule == "cursor" else { return }
        sinceCursorLook += dt
        guard sinceCursorLook >= 0.25 else { return }
        sinceCursorLook = 0
        let mouse = NSEvent.mouseLocation
        // Hysteresis: only turn when the pointer is clearly on the other side.
        guard abs(mouse.x - position.x) > 40, abs(mouse.y - position.y) < 700 else { return }
        let want: Facing = mouse.x > position.x ? .right : .left
        if want != renderer.facing { renderer.facing = want }
    }

    /// Jumps straight to the final step when it leaves the screen (an exit or a move off-screen); otherwise fades out.
    public func exitEarly() {
        guard isRunning, !exitingEarly, abortRemaining == nil else { return }
        exitingEarly = true
        let last = scene.steps.count - 1
        let m = scene.steps[last].motion
        let leaves = m.type == .exit || (m.to ?? "").hasSuffix("offscreen")
        guard leaves else { abort("exit early"); return }
        guard stepIndex < last else { return }
        position = track.position(at: stepElapsed)
        endStep()
        stepElapsed = 0
        beginStep(last)
    }

    private func endStep() {
        for fx in effects { fx.stop() }
        effects = []
    }

    /// The point above the head a bubble points at (overlay space). Clinging to a wall, the body lies sideways.
    private func bubbleHead(_ renderer: SpriteRenderer) -> CGPoint {
        let e = renderer.currentExtents
        guard let r = track.fixedRotation else { return CGPoint(x: 0, y: e.up) }
        // Rotate the head (straight up) by the body's rotation; the sideways body's top is its front/back edge.
        return CGPoint(x: -e.up * sin(r), y: max(e.left, e.right))
    }

    /// Shows the pending line once the head is well inside the screen, so the bubble points at the pet.
    private func speakIfVisible() {
        guard let line = pendingLine, let renderer else { return }
        let step = scene.steps[stepIndex]
        let still = Self.isStill(step)
        // Moving: wait for a still moment later in the scene (if there is none, say it on the move).
        if !still, scene.steps[stepIndex...].contains(where: Self.isStill) { return }
        let head = globalHead(renderer)
        guard display.visibleFrame.insetBy(dx: 4, dy: 0).contains(CGPoint(x: head.x, y: min(head.y, display.visibleFrame.maxY - 1))) else { return }
        pendingLine = nil
        if still {
            // Stay put until the line has been read.
            speechHold = max(0, SpeechBubble.readingTime(line) - (step.duration - stepElapsed))
        }
        if Self.trace {
            FileHandle.standardError.write(Data(String(format: "speak step=%d t=%.2f head=%.0f,%.0f \"%@\"\n", stepIndex, stepElapsed, head.x, head.y, line).utf8))
        }
        bubble?.remove()
        bubble = SpeechBubble(text: line, head: head, display: display)
    }

    /// Just above the pet's head, global coordinates (for its speech bubble).
    private func globalHead(_ renderer: SpriteRenderer) -> CGPoint {
        let h = bubbleHead(renderer)
        return CGPoint(x: position.x + h.x, y: position.y + h.y)
    }

    private func place() {
        let origin = CGPoint(x: position.x - plan.box.pivot.x, y: position.y - plan.box.pivot.y)
        // Clip to the scene's display: with displays side by side or stacked, "off-screen" is on the neighbour.
        // A cross-display flight is meant to be seen on both, so it isn't clipped.
        let clip = track.type == .crossDisplay ? nil : display.frame
        window?.setFrameOrigin(CoordinateSpace.pixelAligned(origin, scale: display.backingScale), clip: clip)
    }

    private func finish(_ outcome: Outcome) {
        if Self.debugStats, startTime > 0 {
            let t = CACurrentMediaTime() - startTime
            FileHandle.standardError.write(Data(String(format: "[pets] %@: %d ticks in %.2fs = %.1f fps (%@)\n",
                                                      scene.id, tickCount, t, Double(tickCount) / max(t, 0.001),
                                                      String(describing: outcome)).utf8))
        }
        link?.invalidate()
        link = nil
        watchdog?.invalidate()
        watchdog = nil
        endStep()
        // The bubble belongs to the pet: it leaves with it.
        bubble?.remove()
        bubble = nil
        renderer?.teardown()
        renderer = nil
        window?.close()
        window = nil
        isRunning = false
        let callback = onFinish
        onFinish = nil
        callback?(outcome)
    }
}

/// M1 debug tool: a static frame at a display's bottom-right edge for a few seconds.
@MainActor
public final class StaticPetPresenter {
    private var window: PetWindowController?
    private var timer: Timer?

    public init() {}

    public func show(pack: LoadedPack?, on display: DisplayGeometry, scale: Double, seconds: Double = 5, outline: Bool) {
        hide()
        let frame = pack.flatMap { p in p.data.clips.resolveOrDefault("idle").flatMap { p.frames[$0.frames[0]] } }
        let size = frame.map { CGSize(width: $0.frame.rect.width * scale, height: $0.frame.rect.height * scale) }
            ?? CGSize(width: 80, height: 100)
        let w = PetWindowController(size: size, outline: outline)
        let layer = CALayer()
        layer.frame = CGRect(origin: .zero, size: size)
        layer.magnificationFilter = .nearest
        if let frame {
            layer.contents = frame.image
        } else {
            layer.backgroundColor = NSColor.systemRed.cgColor
            layer.cornerRadius = 8
        }
        w.rootLayer.addSublayer(layer)
        let v = display.visibleFrame
        w.setFrameOrigin(CGPoint(x: v.maxX - size.width - 24, y: v.minY))
        w.show()
        window = w
        let t = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in MainActor.assumeIsolated { self?.hide() } }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    public func hide() {
        timer?.invalidate()
        timer = nil
        window?.close()
        window = nil
    }
}
