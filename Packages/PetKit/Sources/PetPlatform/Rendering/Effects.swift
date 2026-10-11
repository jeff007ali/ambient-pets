import AppKit
import PetCore
import QuartzCore

/// A running effect. Effects are cheap CA layers / emitters added to the renderer's layer tree.
@MainActor
protocol EffectInstance: AnyObject {
    func update(dt: Double)
    /// Called at the end of the step. Effects wind down on their own (no abrupt cut).
    func stop()
}

@MainActor
struct EffectContext {
    let renderer: SpriteRenderer
    let stepDuration: Double
    let reduceQuality: Bool
    /// Distance from the pivot up to the window's top edge, points. Constant while the window follows the pet.
    let windowTopAbovePivot: Double
    /// Set while the step's motion is a swing: distance from the pivot (feet) to the line's anchor, points.
    var swingRadius: Double?

    /// +1 if the art natively faces right, -1 if left. Effects live in the sprite's native (unmirrored) space,
    /// so "forward" is +x only for right-facing atlases.
    var forward: Double { renderer.pack.data.atlas.facing.sign }

    /// Extent of the current frame in front of the pivot, points.
    var frontReach: Double { forward > 0 ? renderer.currentExtents.right : renderer.currentExtents.left }
}

@MainActor
enum EffectFactory {
    static func make(_ spec: EffectSpec, _ ctx: EffectContext) -> EffectInstance? {
        switch spec.type {
        case .thruster: ThrusterEffect(spec, ctx)
        case .dustPuff: ctx.reduceQuality ? nil : DustPuffEffect(spec, ctx)
        case .squash: SquashEffect(spec, ctx)
        case .tilt: TiltEffect(spec, ctx)
        case .fade: FadeEffect(spec, ctx)
        case .repulsorFlash: RepulsorFlashEffect(spec, ctx)
        case .beam: BeamEffect(spec, ctx)
        case .scanline: ScanlineEffect(spec, ctx)
        case .zzz: ZzzEffect(spec, ctx)
        case .tetherLine: TetherLineEffect(spec, ctx)
        case .projectile: ProjectileEffect(spec, ctx)
        case .overlay: OverlayEffect(spec, ctx)
        default: nil // speech_bubble is handled by the director; planned effects are no-ops.
        }
    }

    /// Resolves an effect's `at` param: a clip point name, an `[x, y]` literal (native px), or the default.
    static func anchor(_ spec: EffectSpec, _ ctx: EffectContext, name: String, default fallback: CGPoint) -> CGPoint {
        if let p = spec.point("at") {
            return CGPoint(x: p.x * ctx.renderer.scale, y: p.y * ctx.renderer.scale)
        }
        return ctx.renderer.point(spec.string("at") ?? name, default: fallback)
    }
}

// MARK: - Shared images

@MainActor
enum EffectImages {
    /// Soft white dot for particles.
    static let particle: CGImage = radial(size: 16, stops: [(1, 1, 1, 1), (1, 1, 1, 0)])
    /// Cyan-white glow for repulsors.
    static let glow: CGImage = radial(size: 64, stops: [(1, 1, 1, 1), (0.55, 0.95, 1, 0.9), (0.2, 0.75, 1, 0)])

    static func radial(size: Int, stops: [(CGFloat, CGFloat, CGFloat, CGFloat)]) -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let colors = stops.map { CGColor(red: $0.0, green: $0.1, blue: $0.2, alpha: $0.3) } as CFArray
        let locations = stops.indices.map { CGFloat($0) / CGFloat(max(stops.count - 1, 1)) }
        let gradient = CGGradient(colorsSpace: space, colors: colors, locations: locations)!
        let c = CGPoint(x: size / 2, y: size / 2)
        ctx.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: CGFloat(size) / 2, options: [])
        return ctx.makeImage()!
    }
}

@MainActor
private func removeLater(_ layer: CALayer, after seconds: Double) {
    Task { @MainActor in
        try? await Task.sleep(for: .seconds(seconds))
        layer.removeFromSuperlayer()
    }
}

// MARK: - Particles

/// Jet flames from the clip's `thruster` point. Direction follows the clip's `thrustDirection` (down / back).
final class ThrusterEffect: EffectInstance {
    let emitter = CAEmitterLayer()

    init(_ spec: EffectSpec, _ ctx: EffectContext) {
        let r = ctx.renderer, s = r.scale
        let back = (spec.string("direction") ?? r.clip?.definition.thrustDirection) == "back"
        emitter.emitterPosition = EffectFactory.anchor(spec, ctx, name: "thruster", default: CGPoint(x: 0, y: 2))
        emitter.emitterShape = .line
        emitter.emitterSize = back ? CGSize(width: 1, height: 10 * s) : CGSize(width: 10 * s, height: 1)
        emitter.renderMode = .additive
        emitter.beginTime = CACurrentMediaTime()

        let cell = CAEmitterCell()
        cell.contents = EffectImages.particle
        cell.birthRate = Float(ctx.reduceQuality ? 35 : 90)
        cell.lifetime = 0.32
        cell.lifetimeRange = 0.1
        cell.velocity = 120 * s
        cell.velocityRange = 30 * s
        // Unflipped layer space: -π/2 points down; "back" is opposite the art's native facing (mirrors with facing).
        cell.emissionLongitude = back ? (ctx.forward > 0 ? .pi : 0) : -.pi / 2
        cell.emissionRange = .pi / 12
        cell.scale = 0.4 * s
        cell.scaleSpeed = -0.9 * s
        cell.color = CGColor(red: 1, green: 0.85, blue: 0.45, alpha: 1)
        cell.greenSpeed = -1.6
        cell.blueSpeed = -2.5
        cell.alphaSpeed = -2.6
        emitter.emitterCells = [cell]
        r.tiltLayer.insertSublayer(emitter, below: r.spriteLayer)
    }

    func update(dt: Double) {}

    func stop() {
        emitter.birthRate = 0
        removeLater(emitter, after: 0.5)
    }
}

/// A short burst of dust at the feet.
final class DustPuffEffect: EffectInstance {
    let emitter = CAEmitterLayer()
    private var elapsed = 0.0

    init(_ spec: EffectSpec, _ ctx: EffectContext) {
        let r = ctx.renderer, s = r.scale
        emitter.emitterPosition = .zero
        emitter.emitterShape = .line
        emitter.emitterSize = CGSize(width: 36 * s, height: 1)
        emitter.beginTime = CACurrentMediaTime()
        let cell = CAEmitterCell()
        cell.contents = EffectImages.particle
        cell.birthRate = 220
        cell.lifetime = 0.6
        cell.lifetimeRange = 0.2
        cell.velocity = 55 * s
        cell.velocityRange = 25 * s
        cell.emissionLongitude = .pi / 2
        cell.emissionRange = .pi / 2.2
        cell.yAcceleration = -60 * s
        cell.scale = 0.55 * s
        cell.scaleSpeed = 0.5 * s
        cell.color = CGColor(red: 0.78, green: 0.72, blue: 0.62, alpha: 0.9)
        cell.alphaSpeed = -1.5
        emitter.emitterCells = [cell]
        r.container.insertSublayer(emitter, below: r.facingLayer)
    }

    func update(dt: Double) {
        elapsed += dt
        if elapsed > 0.08 { emitter.birthRate = 0 }
    }

    func stop() {
        emitter.birthRate = 0
        removeLater(emitter, after: 0.9)
    }
}

// MARK: - Transforms

/// Landing squash-and-stretch around the feet.
final class SquashEffect: EffectInstance {
    init(_ spec: EffectSpec, _ ctx: EffectContext) {
        let a = CAKeyframeAnimation(keyPath: "transform")
        let k = spec.double("amount") ?? 0.2
        a.values = [(1.0, 1.0), (1 + k, 1 - k), (1 - k * 0.3, 1 + k * 0.4), (1.0, 1.0)].map {
            NSValue(caTransform3D: CATransform3DMakeScale($0.0, $0.1, 1))
        }
        a.keyTimes = [0, 0.3, 0.65, 1]
        a.duration = min(spec.double("duration") ?? 0.4, max(ctx.stepDuration, 0.1))
        ctx.renderer.container.add(a, forKey: "squash")
    }

    func update(dt: Double) {}
    func stop() {}
}

/// Lean forward (positive angle) or back, then straighten at the end of the step.
final class TiltEffect: EffectInstance {
    let layer: CALayer

    init(_ spec: EffectSpec, _ ctx: EffectContext) {
        layer = ctx.renderer.tiltLayer
        let radians = (spec.double("angle") ?? 12) * .pi / 180
        // Leaning forward: clockwise for right-facing art, counter-clockwise for left-facing art.
        Self.animate(layer, to: CATransform3DMakeRotation(-radians * ctx.forward, 0, 0, 1))
    }

    static func animate(_ layer: CALayer, to t: CATransform3D) {
        let a = CABasicAnimation(keyPath: "transform")
        a.fromValue = NSValue(caTransform3D: layer.presentation()?.transform ?? layer.transform)
        a.toValue = NSValue(caTransform3D: t)
        a.duration = 0.2
        layer.transform = t
        layer.add(a, forKey: "tilt")
    }

    func update(dt: Double) {}
    func stop() { Self.animate(layer, to: CATransform3DIdentity) }
}

/// `mode`: `out` (default) or `in`, over the step (or `duration`).
final class FadeEffect: EffectInstance {
    init(_ spec: EffectSpec, _ ctx: EffectContext) {
        let fadeIn = spec.string("mode") == "in"
        let layer = ctx.renderer.container
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = fadeIn ? 0 : 1
        a.toValue = fadeIn ? 1 : 0
        a.duration = spec.double("duration") ?? ctx.stepDuration
        layer.opacity = fadeIn ? 1 : 0
        layer.add(a, forKey: "fade")
    }

    func update(dt: Double) {}
    func stop() {}
}

// MARK: - Web line

/// A web line from the clip's `web` point (or `at`) upwards.
/// - No `length`: it runs to the top of the window. Scenes with an unbounded tether get a window that extends a full
///   screen height above the pet, so the line always reaches past the top of the display (drop-from-ceiling).
/// - `length` (native px): a fixed line that fades out at its far end (a swing web going off-screen).
/// - `angle`: degrees from vertical, positive leans forward.
final class TetherLineEffect: EffectInstance {
    let line = CAGradientLayer()

    init(_ spec: EffectSpec, _ ctx: EffectContext) {
        let r = ctx.renderer, s = r.scale
        let e = r.currentExtents
        let origin = EffectFactory.anchor(spec, ctx, name: "web", default: CGPoint(x: 0, y: e.up / s))
        let angle = (spec.double("angle") ?? 0) * .pi / 180
        let fixed = spec.double("length").map { $0 * s }
        // Swinging: the body points at the anchor, so the line runs straight "up" in body space to it.
        let swingLength = ctx.swingRadius.map { max($0 - origin.y, 1) }
        let length = fixed ?? swingLength ?? max((ctx.windowTopAbovePivot - origin.y) / max(cos(angle), 0.2), 1)
        let white = CGColor(red: 0.96, green: 0.97, blue: 1, alpha: 0.95)
        line.colors = fixed == nil ? [white, white] : [white, CGColor(red: 0.96, green: 0.97, blue: 1, alpha: 0)]
        line.startPoint = CGPoint(x: 0.5, y: 0)
        line.endPoint = CGPoint(x: 0.5, y: 1)
        line.anchorPoint = CGPoint(x: 0.5, y: 0)
        line.bounds = CGRect(x: 0, y: 0, width: max(1.6 * s, 2), height: length)
        line.position = origin
        // Rotate the up-vector towards "forward" (art-native space; mirrors with facing).
        line.transform = CATransform3DMakeRotation(-angle * ctx.forward, 0, 0, 1)
        line.shadowColor = CGColor(gray: 0, alpha: 1)
        // A dark outline keeps the white line visible over light windows as well as dark wallpapers.
        line.shadowOpacity = 0.7
        line.shadowRadius = 1.2
        line.shadowOffset = .zero
        let shoot = CABasicAnimation(keyPath: "bounds.size.height")
        shoot.fromValue = 0
        shoot.toValue = length
        shoot.duration = spec.double("shoot") ?? 0.12
        r.tiltLayer.insertSublayer(line, below: r.spriteLayer)
        line.add(shoot, forKey: "shoot")
    }

    func update(dt: Double) {}
    func stop() { removeLater(line, after: 0) }
}

// MARK: - Projectiles

/// Fires a pack clip forward from the `at` point (default `hand`): a web ball, a batarang, a repulsor bolt.
/// Params: `clip` (required), `hit` (clip played where it lands), `speed` (native px/s, 420), `distance` (native px,
/// 240), `delay` (s), `rise` (native px gained over the flight), `spin` (turns per second).
/// It flies in the art's native space inside the tilt layer, so it mirrors with facing for free.
final class ProjectileEffect: EffectInstance {
    let renderer: SpriteRenderer
    let holder = CALayer()
    let sprite = CALayer()
    let flight: ResolvedClip?
    let hit: ResolvedClip?
    let origin: CGPoint
    let forward, speed, distance, delay, rise, spin: Double
    private var elapsed = 0.0
    private var hitElapsed: Double?
    private var done = false

    init(_ spec: EffectSpec, _ ctx: EffectContext) {
        renderer = ctx.renderer
        let r = ctx.renderer, s = r.scale
        flight = spec.string("clip").flatMap { r.pack.data.clips.resolveOrDefault($0) }
        hit = spec.string("hit").flatMap { r.pack.data.clips.resolveOrDefault($0) }
        let e = r.currentExtents
        origin = EffectFactory.anchor(spec, ctx, name: "hand", default: CGPoint(x: ctx.forward * ctx.frontReach / s * 0.9, y: e.up / s * 0.6))
        forward = ctx.forward
        speed = (spec.double("speed") ?? 420) * s
        distance = (spec.double("distance") ?? 240) * s
        delay = spec.double("delay") ?? 0
        rise = (spec.double("rise") ?? 0) * s
        spin = spec.double("spin") ?? 0
        for l in [holder, sprite] { l.actions = noImplicitActions() }
        sprite.magnificationFilter = .nearest
        sprite.minificationFilter = .linear
        holder.bounds = .zero
        holder.anchorPoint = .zero
        holder.position = origin
        holder.isHidden = true
        holder.addSublayer(sprite)
        r.tiltLayer.addSublayer(holder)
    }

    private func show(_ name: String) {
        guard let f = renderer.pack.frames[name] else { return }
        let s = renderer.scale
        sprite.contents = f.image
        sprite.frame = CGRect(x: -f.frame.pivot.x * s, y: -(f.frame.rect.height - f.frame.pivot.y) * s,
                              width: f.frame.rect.width * s, height: f.frame.rect.height * s)
    }

    func update(dt: Double) {
        guard !done else { return }
        elapsed += dt
        let t = elapsed - delay
        guard t >= 0 else { return }
        holder.isHidden = false
        if let he = hitElapsed {
            // Landing animation, played once.
            hitElapsed = he + dt
            guard let hit, Int((he + dt) * hit.definition.fps) < hit.frames.count else { finish(); return }
            show(hit.frameName(at: he + dt))
            return
        }
        let travelled = min(t * speed, distance)
        let u = distance > 0 ? travelled / distance : 1
        holder.position = CGPoint(x: origin.x + forward * travelled, y: origin.y + rise * u)
        if spin != 0 { sprite.transform = CATransform3DMakeRotation(-2 * .pi * spin * t * forward, 0, 0, 1) }
        if let flight { show(flight.frameName(at: t)) }
        if travelled >= distance {
            sprite.transform = CATransform3DIdentity
            if hit != nil { hitElapsed = 0 } else { finish() }
        }
    }

    private func finish() {
        done = true
        holder.removeFromSuperlayer()
    }

    func stop() { finish() }
}

/// Plays a pack clip attached to a body point (default `chest`), in the art's native space so it mirrors with
/// facing. Params: `clip` (required), `at`, `delay` (s), `behind` (draw under the sprite), `loop` (override),
/// `hold` (non-looping clips keep their last frame until the step ends; default true, false hides it when done).
final class OverlayEffect: EffectInstance {
    let renderer: SpriteRenderer
    let holder = CALayer()
    let sprite = CALayer()
    let clip: ResolvedClip?
    let delay: Double
    let loop: Bool?
    let hold: Bool
    private var elapsed = 0.0

    init(_ spec: EffectSpec, _ ctx: EffectContext) {
        renderer = ctx.renderer
        let r = ctx.renderer, s = r.scale
        clip = spec.string("clip").flatMap { r.pack.data.clips.resolveOrDefault($0) }
        delay = spec.double("delay") ?? 0
        loop = spec.bool("loop")
        hold = spec.bool("hold") ?? true
        let e = r.currentExtents
        let origin = EffectFactory.anchor(spec, ctx, name: spec.string("from") ?? "chest",
                                          default: CGPoint(x: ctx.forward * ctx.frontReach / s * 0.5, y: e.up / s * 0.6))
        for l in [holder, sprite] { l.actions = noImplicitActions() }
        sprite.magnificationFilter = .nearest
        sprite.minificationFilter = .linear
        holder.bounds = .zero
        holder.anchorPoint = .zero
        holder.position = origin
        holder.isHidden = true
        holder.addSublayer(sprite)
        if spec.bool("behind") == true { r.tiltLayer.insertSublayer(holder, below: r.spriteLayer) } else { r.tiltLayer.addSublayer(holder) }
    }

    func update(dt: Double) {
        elapsed += dt
        let t = elapsed - delay
        guard t >= 0, let clip else { return }
        let looping = loop ?? clip.definition.loop
        if !looping, !hold, Int(t * clip.definition.fps) >= clip.frames.count { holder.isHidden = true; return }
        holder.isHidden = false
        var name = clip.frameName(at: t)
        if loop == false { name = clip.frames[min(Int(t * clip.definition.fps), clip.frames.count - 1)] }
        if loop == true { name = clip.frames[Int(t * clip.definition.fps) % clip.frames.count] }
        guard let f = renderer.pack.frames[name] else { return }
        let s = renderer.scale
        sprite.contents = f.image
        sprite.frame = CGRect(x: -f.frame.pivot.x * s, y: -(f.frame.rect.height - f.frame.pivot.y) * s,
                              width: f.frame.rect.width * s, height: f.frame.rect.height * s)
    }

    func stop() { removeLater(holder, after: 0) }
}

// MARK: - Iron Man-ish weapons and HUD

/// Glow flashes at the clip's `hand` point. `count` flashes (default 2).
final class RepulsorFlashEffect: EffectInstance {
    let glow = CALayer()

    init(_ spec: EffectSpec, _ ctx: EffectContext) {
        let r = ctx.renderer, s = r.scale
        let e = r.currentExtents
        let size = (spec.double("size") ?? 30) * s
        glow.contents = EffectImages.glow
        glow.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        glow.position = EffectFactory.anchor(spec, ctx, name: "hand",
                                             default: CGPoint(x: ctx.forward * ctx.frontReach / s * 0.9, y: e.up / s * 0.6))
        glow.opacity = 0
        glow.compositingFilter = "screenBlendMode"
        let count = max(spec.double("count") ?? 2, 1)
        let flash = CAKeyframeAnimation(keyPath: "opacity")
        flash.values = [0, 1, 0.9, 0]
        flash.keyTimes = [0, 0.15, 0.4, 1]
        let grow = CAKeyframeAnimation(keyPath: "transform.scale")
        grow.values = [0.3, 1.25, 0.6]
        let group = CAAnimationGroup()
        group.animations = [flash, grow]
        group.duration = min(0.35, ctx.stepDuration / count)
        group.repeatCount = Float(count)
        r.tiltLayer.addSublayer(glow)
        glow.add(group, forKey: "flash")
    }

    func update(dt: Double) {}
    func stop() { removeLater(glow, after: 0.4) }
}

/// A beam shooting forward from the `hand` point (or `chest` for a unibeam). `length` in native px.
final class BeamEffect: EffectInstance {
    let beam = CAGradientLayer()

    init(_ spec: EffectSpec, _ ctx: EffectContext) {
        let r = ctx.renderer, s = r.scale
        let e = r.currentExtents
        let origin = EffectFactory.anchor(spec, ctx, name: spec.string("from") ?? "hand",
                                          default: CGPoint(x: ctx.forward * ctx.frontReach / s * 0.9, y: e.up / s * 0.6))
        let length = (spec.double("length") ?? 150) * s, thickness = (spec.double("thickness") ?? 7) * s
        beam.colors = [CGColor(red: 0.3, green: 0.85, blue: 1, alpha: 0.6), CGColor(red: 1, green: 1, blue: 1, alpha: 1),
                       CGColor(red: 0.3, green: 0.85, blue: 1, alpha: 0.6)]
        beam.startPoint = CGPoint(x: 0.5, y: 0)
        beam.endPoint = CGPoint(x: 0.5, y: 1)
        beam.cornerRadius = thickness / 2
        beam.anchorPoint = CGPoint(x: ctx.forward > 0 ? 0 : 1, y: 0.5)
        beam.position = origin
        beam.bounds = CGRect(x: 0, y: 0, width: length, height: thickness)
        beam.shadowColor = CGColor(red: 0.3, green: 0.85, blue: 1, alpha: 1)
        beam.shadowOpacity = 0.9
        beam.shadowRadius = 4 * s
        beam.shadowOffset = .zero
        let grow = CABasicAnimation(keyPath: "bounds.size.width")
        grow.fromValue = 0
        grow.toValue = length
        grow.duration = 0.14
        let flicker = CABasicAnimation(keyPath: "opacity")
        flicker.fromValue = 1
        flicker.toValue = 0.75
        flicker.duration = 0.06
        flicker.autoreverses = true
        flicker.repeatCount = .infinity
        r.tiltLayer.addSublayer(beam)
        beam.add(grow, forKey: "grow")
        beam.add(flicker, forKey: "flicker")
    }

    func update(dt: Double) {}

    func stop() {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = 0.15
        beam.opacity = 0
        beam.add(fade, forKey: "fadeOut")
        removeLater(beam, after: 0.2)
    }
}

/// HUD scan: corner brackets around the sprite and a sweeping line.
final class ScanlineEffect: EffectInstance {
    let hud = CALayer()

    init(_ spec: EffectSpec, _ ctx: EffectContext) {
        let r = ctx.renderer
        let e = r.currentExtents.mirrorSafe
        let box = CGRect(x: -e.left - 4, y: -e.down - 2, width: e.left + e.right + 8, height: e.up + e.down + 6)
        let cyan = CGColor(red: 0.35, green: 0.9, blue: 1, alpha: 0.95)
        hud.actions = noImplicitActions()

        let brackets = CAShapeLayer()
        let path = CGMutablePath()
        let c = min(box.width, box.height) * 0.18
        for (x, y, dx, dy) in [(box.minX, box.minY, 1.0, 1.0), (box.maxX, box.minY, -1, 1), (box.minX, box.maxY, 1, -1), (box.maxX, box.maxY, -1, -1)] {
            path.move(to: CGPoint(x: x, y: y + dy * c))
            path.addLine(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x + dx * c, y: y))
        }
        brackets.path = path
        brackets.strokeColor = cyan
        brackets.fillColor = nil
        brackets.lineWidth = 1.5
        hud.addSublayer(brackets)

        let line = CALayer()
        line.backgroundColor = cyan
        line.bounds = CGRect(x: 0, y: 0, width: box.width, height: 1.5)
        line.position = CGPoint(x: box.midX, y: box.minY)
        line.shadowColor = cyan
        line.shadowOpacity = 1
        line.shadowRadius = 3
        line.shadowOffset = .zero
        let sweep = CABasicAnimation(keyPath: "position.y")
        sweep.fromValue = box.minY
        sweep.toValue = box.maxY
        sweep.duration = spec.double("period") ?? 0.9
        sweep.autoreverses = true
        sweep.repeatCount = .infinity
        line.add(sweep, forKey: "sweep")
        hud.addSublayer(line)

        let blink = CABasicAnimation(keyPath: "opacity")
        blink.fromValue = 0
        blink.toValue = 1
        blink.duration = 0.25
        hud.add(blink, forKey: "in")
        r.container.addSublayer(hud)
    }

    func update(dt: Double) {}

    func stop() {
        hud.opacity = 0
        removeLater(hud, after: 0.1)
    }
}

/// Floating "z"s from the `head` point.
final class ZzzEffect: EffectInstance {
    let renderer: SpriteRenderer
    let origin: CGPoint
    let drift: Double
    private var untilNext = 0.0
    private var layers: [CALayer] = []

    init(_ spec: EffectSpec, _ ctx: EffectContext) {
        renderer = ctx.renderer
        let e = ctx.renderer.currentExtents, s = ctx.renderer.scale
        origin = EffectFactory.anchor(spec, ctx, name: "head", default: CGPoint(x: ctx.forward * ctx.frontReach / s * 0.3, y: e.up / s * 0.95))
        drift = 14 * ctx.forward
    }

    func update(dt: Double) {
        untilNext -= dt
        guard untilNext <= 0 else { return }
        untilNext = 0.9
        let z = CATextLayer()
        z.string = "z"
        z.font = NSFont.boldSystemFont(ofSize: 14)
        z.fontSize = 14
        z.foregroundColor = NSColor.white.cgColor
        z.shadowColor = NSColor.black.cgColor
        z.shadowOpacity = 0.6
        z.shadowRadius = 1
        z.shadowOffset = .zero
        z.contentsScale = renderer.container.contentsScale
        z.bounds = CGRect(x: 0, y: 0, width: 14, height: 18)
        z.position = origin
        z.opacity = 0
        let rise = CABasicAnimation(keyPath: "position")
        rise.fromValue = NSValue(point: origin)
        rise.toValue = NSValue(point: CGPoint(x: origin.x + drift, y: origin.y + 30))
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 0]
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.6
        grow.toValue = 1.3
        let g = CAAnimationGroup()
        g.animations = [rise, fade, grow]
        g.duration = 1.8
        renderer.tiltLayer.addSublayer(z)
        z.add(g, forKey: "z")
        removeLater(z, after: 1.8)
    }

    func stop() {}
}
