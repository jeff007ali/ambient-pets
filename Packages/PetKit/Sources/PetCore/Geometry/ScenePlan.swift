import CoreGraphics
import Foundation

public enum HorizontalSide: String, Sendable, Hashable {
    case left, right
    public var opposite: HorizontalSide { self == .left ? .right : .left }
}

/// Named points that motion `from` / `to` fields can refer to.
public enum AnchorRef {
    public static let known: Set<String> = [
        "anchor", "current", "ground", "center", "screen_center",
        "top_offscreen", "bottom_offscreen", "left_offscreen", "right_offscreen",
        "side_offscreen", "opposite_offscreen", "wall", "wall_below", "wall_high",
    ]
}

/// Where a scene plays: the display, the spawn anchor, and the side the pet comes from.
public struct ScenePlan: Sendable, Hashable {
    public var display: DisplayGeometry
    public var box: PetBox
    /// The spawn point for the pivot (feet), AppKit global coordinates.
    public var anchor: CGPoint
    /// The screen side the pet enters from (`side_offscreen`).
    public var side: HorizontalSide
    /// Every connected display (for `cross_display`).
    public var allDisplays: [DisplayGeometry] = []

    public init(display: DisplayGeometry, box: PetBox, anchor: CGPoint, side: HorizontalSide) {
        self.display = display
        self.box = box
        self.anchor = anchor
        self.side = side
    }

    /// Resolves an `AnchorRef` name to a pivot position. Off-screen points keep the whole window (sprite and
    /// effects) outside the display's full frame.
    public func resolve(_ ref: String, current: CGPoint) -> CGPoint? {
        let frame = display.frame, visible = display.visibleFrame
        switch ref {
        case "anchor": return anchor
        case "current": return current
        case "ground": return CGPoint(x: current.x, y: visible.minY)
        case "center": return CGPoint(x: visible.midX, y: anchor.y)
        case "screen_center": return CGPoint(x: visible.midX, y: visible.midY)
        case "top_offscreen": return CGPoint(x: anchor.x, y: frame.maxY + box.pivot.y)
        case "bottom_offscreen": return CGPoint(x: anchor.x, y: frame.minY - (box.size.height - box.pivot.y))
        case "left_offscreen": return offscreen(.left)
        case "right_offscreen": return offscreen(.right)
        case "side_offscreen": return offscreen(side)
        case "opposite_offscreen": return offscreen(side.opposite)
        // Wall points: the pivot (feet) on the `side` edge of the visible frame.
        case "wall": return CGPoint(x: wallX, y: anchor.y)
        case "wall_below": return CGPoint(x: wallX, y: frame.minY - box.size.height)
        case "wall_high": return CGPoint(x: wallX, y: min(anchor.y + visible.height * 0.3, visible.maxY - box.sprite.right - 8))
        default: return nil
        }
    }

    var wallX: CGFloat { side == .left ? display.visibleFrame.minX : display.visibleFrame.maxX }

    private func offscreen(_ s: HorizontalSide) -> CGPoint {
        let frame = display.frame
        switch s {
        case .left: return CGPoint(x: frame.minX - (box.size.width - box.pivot.x), y: anchor.y)
        case .right: return CGPoint(x: frame.maxX + box.pivot.x, y: anchor.y)
        }
    }
}

/// A vertical slice of the screen, so pets playing at the same time don't land on top of each other.
public struct ScreenLane: Sendable, Hashable {
    public var index: Int
    public var count: Int
    public init(index: Int, count: Int) {
        self.index = max(0, min(index, count - 1))
        self.count = max(count, 1)
    }

    /// The lane's slice of `frame`.
    public func slice(of frame: CGRect) -> CGRect {
        let w = frame.width / Double(count)
        return CGRect(x: frame.minX + w * Double(index), y: frame.minY, width: w, height: frame.height)
    }

    /// Which screen edge this lane touches, if any.
    public var edge: HorizontalSide? {
        if count == 1 { return nil }
        if index == 0 { return .left }
        return index == count - 1 ? .right : nil
    }
}

/// v1 planner: picks an anchor for the scene's preferred region. The full obstacle-aware version comes in M5.
public enum ScenePlanner {
    public static func plan(region: SceneRegion, display: DisplayGeometry, box: PetBox, rng: RandomSource,
                            lane: ScreenLane? = nil) -> ScenePlan {
        var region = region
        // A middle lane touches no screen edge, so edge scenes play from the bottom instead.
        if region == .sideEdge, let lane, lane.count > 1, lane.edge == nil { region = .bottomEdge }
        let v = display.visibleFrame
        // Horizontal range for anchors: the lane's slice of the visible frame (whole frame without a lane).
        let lv = lane.map { $0.slice(of: v) } ?? v
        let s = box.sprite
        let margin = max(s.left, s.right) + 16

        func range(_ lo: Double, _ hi: Double) -> ClosedRange<Double> { lo <= hi ? lo...hi : ((lo + hi) / 2)...((lo + hi) / 2) }
        func randomSide() -> HorizontalSide { lane?.edge ?? (rng.chance(0.5) ? .left : .right) }
        func xRange(_ inset: Double) -> ClosedRange<Double> { range(max(lv.minX, v.minX + inset), min(lv.maxX, v.maxX - inset)) }

        let anchor: CGPoint
        var side: HorizontalSide
        switch region {
        case .sideEdge:
            side = randomSide()
            // Pivot just inside the edge, so a bit over half the sprite shows.
            let x = side == .left ? v.minX + s.right * 0.15 : v.maxX - s.right * 0.15
            anchor = CGPoint(x: x, y: rng.double(in: range(v.minY + v.height * 0.05, v.minY + v.height * 0.5)))
        case .topEdge:
            anchor = CGPoint(x: rng.double(in: xRange(margin)), y: v.maxY - s.up - 4)
            side = lane?.edge ?? (anchor.x < v.midX ? .left : .right)
        case .air:
            anchor = CGPoint(x: rng.double(in: lane == nil ? range(v.minX + v.width * 0.2, v.maxX - v.width * 0.2) : xRange(margin)),
                             y: rng.double(in: range(v.minY + v.height * 0.45, v.maxY - s.up - 20)))
            side = randomSide()
        case .anywhere:
            anchor = CGPoint(x: rng.double(in: xRange(margin)),
                             y: rng.double(in: range(v.minY, v.maxY - s.up - 8)))
            side = randomSide()
        default: // bottom_edge and unknown regions
            anchor = CGPoint(x: rng.double(in: xRange(margin)), y: v.minY)
            // Come in from the nearer side (or the lane's own edge): shorter flights, no crossing other pets.
            side = lane?.edge ?? (anchor.x < v.midX ? .left : .right)
        }
        return ScenePlan(display: display, box: box, anchor: anchor, side: side)
    }
}
