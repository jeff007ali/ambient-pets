import CoreGraphics
import Foundation

/// Something the pet should stay away from (AppKit global coordinates).
public struct Obstacle: Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable {
        /// The text caret / focused field: never cover it.
        case caret
        /// The mouse pointer's neighbourhood.
        case cursor
        /// The frontmost window's content: allowed, but edges are better.
        case activeWindow
        /// A video or presentation window: blocked entirely.
        case video
    }

    public var rect: CGRect
    public var kind: Kind

    public init(rect: CGRect, kind: Kind) {
        self.rect = rect
        self.kind = kind
    }

    var weight: Double {
        switch kind {
        case .caret: 20
        case .cursor: 4
        case .activeWindow: 0.15
        case .video: 50
        }
    }

    var blocking: Bool { kind == .caret || kind == .video }
}

/// Obstacle-aware placement (plan §4.6): tries several candidate anchors for the scene's region and keeps the one
/// whose resting rect overlaps the obstacles least. Blocking obstacles (caret, video) disqualify a candidate.
public enum SafeRegionPlanner {
    public struct Result: Sendable {
        public var plan: ScenePlan
        public var score: Double
        /// All candidates tried, for the debug overlay.
        public var candidates: [CGPoint]
    }

    /// Where the pet rests at `anchor`: its sprite rect, padded.
    public static func restingRect(anchor: CGPoint, box: PetBox, padding: Double = 24) -> CGRect {
        let s = box.sprite
        return CGRect(x: anchor.x - s.left, y: anchor.y - s.down, width: s.left + s.right, height: s.up + s.down)
            .insetBy(dx: -padding, dy: -padding)
    }

    /// Overlap penalty of a resting rect against obstacles, or nil if a blocking obstacle is hit.
    public static func score(_ rect: CGRect, obstacles: [Obstacle]) -> Double? {
        var total = 0.0
        let area = max(rect.width * rect.height, 1)
        for o in obstacles {
            let i = rect.intersection(o.rect)
            guard !i.isNull, i.width > 0, i.height > 0 else { continue }
            if o.blocking { return nil }
            total += o.weight * (i.width * i.height) / area
        }
        return total
    }

    /// - Returns: the best plan, or nil when every candidate hits a blocking obstacle (skip this appearance).
    public static func plan(region: SceneRegion, display: DisplayGeometry, box: PetBox, rng: RandomSource,
                            lane: ScreenLane? = nil, obstacles: [Obstacle], attempts: Int = 12, headroom: Double = 0) -> Result? {
        guard !obstacles.isEmpty else {
            let p = ScenePlanner.plan(region: region, display: display, box: box, rng: rng, lane: lane, headroom: headroom)
            return Result(plan: p, score: 0, candidates: [p.anchor])
        }
        var best: (ScenePlan, Double)?
        var tried: [CGPoint] = []
        for _ in 0..<max(attempts, 1) {
            let p = ScenePlanner.plan(region: region, display: display, box: box, rng: rng, lane: lane, headroom: headroom)
            tried.append(p.anchor)
            guard let s = score(restingRect(anchor: p.anchor, box: box), obstacles: obstacles) else { continue }
            if best == nil || s < best!.1 { best = (p, s) }
            if s == 0 { break }
        }
        return best.map { Result(plan: $0.0, score: $0.1, candidates: tried) }
    }
}
