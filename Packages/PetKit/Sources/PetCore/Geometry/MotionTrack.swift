import CoreGraphics
import Foundation

/// A motion primitive resolved for one step: start/end points plus the curve. Pure and deterministic once built.
public struct MotionTrack: Sendable, Hashable {
    public var type: MotionType
    public var start: CGPoint
    public var end: CGPoint
    public var duration: Double
    public var curve: Easing
    /// Vertical arc added on top of the path (hop / arc), points.
    public var height: Double
    /// Hover bob, points / Hz.
    public var amplitude: Double
    public var frequency: Double
    /// Set for `swing`: the pivot of the pendulum and the angles swept.
    public var pendulum: Pendulum?
    /// Constant body rotation (counter-clockwise radians), e.g. ±90° while clinging to a wall.
    public var fixedRotation: Double?
    /// Facing the motion wants (e.g. "head first" while crawling up a wall).
    public var preferredFacing: Facing?
    /// `cross_display` without a shared edge: leave at `exit`, reappear at `entry`, at progress `at` (0…1).
    public var hop: Hop?

    public struct Hop: Sendable, Hashable {
        public var at: Double
        public var exit: CGPoint
        public var entry: CGPoint
    }

    /// Position = center + radius · (sin a, −cos a). The body points at `center`, i.e. it is rotated by `a`
    /// (counter-clockwise, radians).
    public struct Pendulum: Sendable, Hashable {
        public var center: CGPoint
        public var radius: Double
        public var from: Double
        public var to: Double
    }

    public init(type: MotionType, start: CGPoint, end: CGPoint, duration: Double, curve: Easing,
                height: Double = 0, amplitude: Double = 0, frequency: Double = 0) {
        self.type = type
        self.start = start
        self.end = end
        self.duration = duration
        self.curve = curve
        self.height = height
        self.amplitude = amplitude
        self.frequency = frequency
    }

    public func position(at elapsed: Double) -> CGPoint {
        let u = duration > 0 ? min(max(elapsed / duration, 0), 1) : 1
        let k = curve.apply(u)
        if let p = pendulum {
            let a = p.from + (p.to - p.from) * k
            return CGPoint(x: p.center.x + p.radius * sin(a), y: p.center.y - p.radius * cos(a))
        }
        if let h = hop {
            if k < h.at {
                let f = h.at > 0 ? k / h.at : 1
                return CGPoint(x: start.x + (h.exit.x - start.x) * f, y: start.y + (h.exit.y - start.y) * f)
            }
            let f = h.at < 1 ? (k - h.at) / (1 - h.at) : 1
            return CGPoint(x: h.entry.x + (end.x - h.entry.x) * f, y: h.entry.y + (end.y - h.entry.y) * f)
        }
        var p = CGPoint(x: start.x + (end.x - start.x) * k, y: start.y + (end.y - start.y) * k)
        if height != 0 { p.y += height * 4 * u * (1 - u) }
        if amplitude != 0 {
            // Envelope keeps the bob continuous with the neighbouring steps.
            let envelope = min(1, u * 4, (1 - u) * 4)
            p.y += amplitude * sin(2 * .pi * frequency * elapsed) * envelope
        }
        return p
    }

    /// Opacity multiplier: dips to 0 around a cross-display hop, 1 otherwise.
    public func opacity(at elapsed: Double) -> Double {
        guard let h = hop, duration > 0 else { return 1 }
        let k = curve.apply(min(max(elapsed / duration, 0), 1))
        let window = 0.08
        return min(1, abs(k - h.at) / window)
    }

    /// True while the motion drives body rotation (swing or cling).
    public var rotates: Bool { pendulum != nil || fixedRotation != nil }

    /// Body rotation (counter-clockwise radians) at `elapsed`: non-zero only while swinging or clinging.
    public func rotation(at elapsed: Double) -> Double {
        if let r = fixedRotation { return r }
        guard let p = pendulum else { return 0 }
        let u = duration > 0 ? min(max(elapsed / duration, 0), 1) : 1
        return p.from + (p.to - p.from) * curve.apply(u)
    }

    /// Direction of horizontal travel, if any.
    public var horizontalDirection: Facing? {
        let dx = end.x - start.x
        return dx > 1 ? .right : (dx < -1 ? .left : nil)
    }

    /// Builds the track for a step.
    /// - Parameters:
    ///   - current: the pivot position at the end of the previous step.
    ///   - scale: native sprite px → points (for heights, speeds, offsets).
    public static func make(spec: MotionSpec, duration: Double, current: CGPoint, plan: ScenePlan,
                            scale: Double, rng: RandomSource, heading: Facing = .right) -> MotionTrack {
        func point(_ ref: String?, _ fallback: CGPoint) -> CGPoint {
            guard let ref else { return fallback }
            return plan.resolve(ref, current: current) ?? fallback
        }
        func target(_ defaultRef: String) -> CGPoint {
            if spec.to == nil, let a = spec.advance, a.count == 2 {
                return CGPoint(x: current.x + a[0] * scale * heading.sign, y: current.y + a[1] * scale)
            }
            var p = point(spec.to ?? defaultRef, current)
            if let o = spec.offset, o.count == 2 {
                p.x += o[0] * scale
                p.y += o[1] * scale
            }
            return p
        }
        let start = point(spec.from, current)

        switch spec.type {
        case .enter:
            return MotionTrack(type: .enter, start: point(spec.from ?? "side_offscreen", current), end: target("anchor"),
                               duration: duration, curve: spec.curve ?? .easeOut)
        case .exit:
            return MotionTrack(type: .exit, start: start, end: target("side_offscreen"),
                               duration: duration, curve: spec.curve ?? .easeIn)
        case .moveTo:
            return MotionTrack(type: .moveTo, start: start, end: target("anchor"),
                               duration: duration, curve: spec.curve ?? .easeInOut)
        case .drop:
            return MotionTrack(type: .drop, start: start, end: target("ground"),
                               duration: duration, curve: spec.curve ?? .easeIn)
        case .arc:
            return MotionTrack(type: .arc, start: start, end: target("anchor"), duration: duration,
                               curve: spec.curve ?? .easeInOut, height: (spec.height ?? 60) * scale)
        case .hop:
            let end = spec.to == nil ? start : target("current")
            return MotionTrack(type: .hop, start: start, end: end, duration: duration,
                               curve: spec.curve ?? .linear, height: (spec.height ?? 20) * scale)
        case .swing:
            // Direction: towards `to` if given, else the current heading.
            var dir = heading.sign
            if let to = spec.to, let t = plan.resolve(to, current: current), abs(t.x - start.x) > 1 { dir = t.x > start.x ? 1 : -1 }
            let half = (spec.sweep ?? 100) / 2 * .pi / 180
            var r = (spec.radius ?? 220) * scale
            if spec.attach == "top" {
                // Anchor on the screen's top edge: centre.y = start.y + r·cos(half).
                r = max((plan.display.frame.maxY - start.y) / cos(half), 40 * scale)
            }
            let a0 = -dir * half, a1 = dir * half
            let center = CGPoint(x: start.x - r * sin(a0), y: start.y + r * cos(a0))
            var t = MotionTrack(type: .swing, start: start, end: CGPoint(x: center.x + r * sin(a1), y: center.y - r * cos(a1)),
                                duration: duration, curve: spec.curve ?? .easeInOut)
            t.pendulum = Pendulum(center: center, radius: r, from: a0, to: a1)
            return t
        case .cling:
            // Feet on the wall: left wall → rotate −90° (feet point left), right wall → +90°.
            let wall = plan.side
            let from = point(spec.from, current)
            let to = target("wall")
            var t = MotionTrack(type: .cling, start: from, end: to, duration: duration, curve: spec.curve ?? .easeInOut)
            t.fixedRotation = wall == .left ? -.pi / 2 : .pi / 2
            // Head first: rotated −90°, facing left points up; rotated +90°, facing right points up.
            let up = to.y >= from.y - 1
            t.preferredFacing = (wall == .left) == up ? .left : .right
            return t
        case .crossDisplay:
            return crossDisplay(spec: spec, duration: duration, current: current, plan: plan, heading: heading)
        case .hover:
            return MotionTrack(type: .hover, start: start, end: start, duration: duration, curve: .linear,
                               amplitude: (spec.amplitude ?? 5) * scale, frequency: spec.frequency ?? 0.8)
        case .walk:
            let v = plan.display.visibleFrame
            var end = start
            if spec.to != nil {
                end.x = target("anchor").x
            } else {
                let distance = spec.distance.map { $0 * scale } ?? (spec.speed ?? 60) * scale * duration
                let towardCenter: Double = start.x < v.midX ? 1 : -1
                let dir: Double = switch spec.direction {
                case "left": -1
                case "right": 1
                case "away_from_center": -towardCenter
                case "random": rng.chance(0.5) ? 1 : -1
                default: towardCenter
                }
                end.x = start.x + dir * distance
            }
            let lo = v.minX + plan.box.sprite.left + 4, hi = v.maxX - plan.box.sprite.right - 4
            if lo <= hi { end.x = min(max(end.x, lo), hi) }
            return MotionTrack(type: .walk, start: start, end: end, duration: duration, curve: spec.curve ?? .linear)
        default:
            // `none`, plus planned-but-unimplemented primitives, hold still.
            return MotionTrack(type: spec.type, start: start, end: start, duration: duration, curve: .linear)
        }
    }

    /// Leaves this display towards the next one in the heading direction: straight through a shared edge, or a fade
    /// hop to the nearest display that way. Ends off-screen past the far side of the target display.
    static func crossDisplay(spec: MotionSpec, duration: Double, current: CGPoint, plan: ScenePlan, heading: Facing) -> MotionTrack {
        let graph = DisplayGraph(plan.allDisplays.isEmpty ? [plan.display] : plan.allDisplays)
        var side: HorizontalSide = heading == .right ? .right : .left
        switch spec.direction {
        case "left": side = .left
        case "right": side = .right
        default:
            // Head for a display that's actually there (prefer the current heading).
            if graph.next(from: plan.display.id, heading: side) == nil, graph.next(from: plan.display.id, heading: side.opposite) != nil {
                side = side.opposite
            }
        }
        let a = plan.display.frame
        let halfW = plan.box.size.width
        let exitX = side == .right ? a.maxX + plan.box.pivot.x : a.minX - (halfW - plan.box.pivot.x)
        guard let (b, continuous) = graph.next(from: plan.display.id, heading: side) else {
            // Single display: just fly off this one.
            return MotionTrack(type: .crossDisplay, start: current, end: CGPoint(x: exitX, y: current.y), duration: duration, curve: spec.curve ?? .linear)
        }
        let bv = b.visibleFrame
        // Keep the flight height inside the target display's visible frame.
        let y = min(max(current.y, bv.minY + bv.height * 0.2), bv.maxY - plan.box.sprite.up - 20)
        let farX = side == .right ? b.frame.maxX + plan.box.pivot.x : b.frame.minX - (halfW - plan.box.pivot.x)
        var t = MotionTrack(type: .crossDisplay, start: current, end: CGPoint(x: farX, y: y), duration: duration, curve: spec.curve ?? .linear)
        if !continuous {
            let entryX = side == .right ? b.frame.minX - (halfW - plan.box.pivot.x) : b.frame.maxX + plan.box.pivot.x
            let total = abs(exitX - current.x) + abs(farX - entryX)
            t.hop = Hop(at: total > 0 ? abs(exitX - current.x) / total : 0.5,
                        exit: CGPoint(x: exitX, y: current.y), entry: CGPoint(x: entryX, y: y))
        }
        return t
    }

    /// Facing for a step given its rule (`StepDefinition.facing`).
    public static func facing(rule: String?, track: MotionTrack, current: Facing, plan: ScenePlan) -> Facing {
        let midX = plan.display.visibleFrame.midX
        let towardCenter: Facing = track.start.x < midX ? .right : .left
        switch rule {
        case "left": return .left
        case "right": return .right
        case "toward_center": return towardCenter
        case "away_from_center": return towardCenter.opposite
        case "keep": return current
        default: return track.preferredFacing ?? track.horizontalDirection ?? current
        }
    }
}
