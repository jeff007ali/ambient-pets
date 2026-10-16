import CoreGraphics
import Foundation
import Testing
@testable import PetCore

// A 1440×900 primary display and a 1920×1080 display stacked above it, offset to the right.
let primary = DisplayGeometry(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                              visibleFrame: CGRect(x: 0, y: 70, width: 1440, height: 805), backingScale: 2)
let upper = DisplayGeometry(id: 2, frame: CGRect(x: 200, y: 900, width: 1920, height: 1080),
                            visibleFrame: CGRect(x: 200, y: 900, width: 1920, height: 1055), backingScale: 1)

@Suite struct CoordinateSpaceTests {
    @Test func primaryHeightUsesDisplayAtOrigin() {
        #expect(CoordinateSpace.primaryHeight(of: [upper, primary]) == 900)
    }

    @Test func pointFlipsAboutPrimaryHeight() {
        let p = CoordinateSpace.appKitToCG(CGPoint(x: 10, y: 0), primaryHeight: 900)
        #expect(p == CGPoint(x: 10, y: 900))
        #expect(CoordinateSpace.cgToAppKit(p, primaryHeight: 900) == CGPoint(x: 10, y: 0))
    }

    @Test func primaryDisplayFrameMapsToOrigin() {
        #expect(CoordinateSpace.appKitToCG(primary.frame, primaryHeight: 900) == CGRect(x: 0, y: 0, width: 1440, height: 900))
    }

    @Test func displayAboveThePrimaryHasNegativeCGY() {
        // AppKit y 900…1980 → CG y -1080…0.
        let r = CoordinateSpace.appKitToCG(upper.frame, primaryHeight: 900)
        #expect(r == CGRect(x: 200, y: -1080, width: 1920, height: 1080))
    }

    @Test func rectRoundTrips() {
        let r = CGRect(x: -300, y: 123.5, width: 77, height: 41)
        let back = CoordinateSpace.cgToAppKit(CoordinateSpace.appKitToCG(r, primaryHeight: 900), primaryHeight: 900)
        #expect(back == r)
    }

    @Test func menuBarIsAtTopInAppKitAndCG() {
        // The menu bar strip: AppKit y 875…900 (top of primary) ↔ CG y 0…25.
        let menuBar = CGRect(x: 0, y: 875, width: 1440, height: 25)
        #expect(CoordinateSpace.appKitToCG(menuBar, primaryHeight: 900).minY == 0)
    }

    @Test func pixelAlignment() {
        #expect(CoordinateSpace.pixelAligned(CGPoint(x: 10.3, y: 4.74), scale: 2) == CGPoint(x: 10.5, y: 4.5))
        #expect(CoordinateSpace.pixelAligned(CGPoint(x: 10.3, y: 4.74), scale: 1) == CGPoint(x: 10, y: 5))
    }
}

@Suite struct PetBoxTests {
    @Test func pivotAndSizeIncludePadding() {
        let e = SpriteExtents(left: 40, right: 50, up: 100, down: 0)
        let box = PetBox.make(extents: e, scale: 1, padding: .init(side: 10, top: 20, bottom: 30))
        // Mirror-safe: both sides use 50.
        #expect(box.pivot == CGPoint(x: 60, y: 30))
        #expect(box.size == CGSize(width: 120, height: 150))
    }

    @Test func minWidthWidensSymmetrically() {
        let e = SpriteExtents(left: 20, right: 20, up: 50, down: 0)
        let box = PetBox.make(extents: e, scale: 1, padding: .init(side: 0, top: 0, bottom: 0), minWidth: 200)
        #expect(box.size.width == 200)
        #expect(box.pivot.x == 100)
    }

    @Test func windowFramePlacesPivot() {
        let box = PetBox(size: CGSize(width: 100, height: 80), pivot: CGPoint(x: 50, y: 10), sprite: .zero)
        #expect(box.windowFrame(pivotAt: CGPoint(x: 500, y: 70)) == CGRect(x: 450, y: 60, width: 100, height: 80))
    }
}

@Suite struct MotionTests {
    let box = PetBox.make(extents: SpriteExtents(left: 30, right: 30, up: 100, down: 0), scale: 1,
                          padding: .init(side: 20, top: 20, bottom: 40))

    func plan(_ region: SceneRegion = .bottomEdge, seed: UInt64 = 1) -> ScenePlan {
        ScenePlanner.plan(region: region, display: primary, box: box, rng: SeededRandom(seed: seed))
    }

    @Test func bottomEdgeAnchorStandsOnVisibleFrame() {
        for seed in 0..<50 {
            let p = plan(seed: UInt64(seed))
            #expect(p.anchor.y == primary.visibleFrame.minY)
            #expect(p.anchor.x - box.sprite.left >= primary.visibleFrame.minX)
            #expect(p.anchor.x + box.sprite.right <= primary.visibleFrame.maxX)
        }
    }

    @Test func offscreenPointsKeepWholeWindowOutsideTheDisplay() {
        let p = plan()
        for ref in ["top_offscreen", "bottom_offscreen", "left_offscreen", "right_offscreen"] {
            let point = p.resolve(ref, current: p.anchor)!
            let window = box.windowFrame(pivotAt: point)
            #expect(!window.intersects(primary.frame), "\(ref) window \(window) overlaps the display")
            // …but only just: it touches the edge, so the pet enters without delay.
            #expect(window.insetBy(dx: -1, dy: -1).intersects(primary.frame), "\(ref) is further than needed")
        }
    }

    @Test func sideAndOppositeAreDifferentSides() {
        let p = plan()
        let a = p.resolve("side_offscreen", current: .zero)!, b = p.resolve("opposite_offscreen", current: .zero)!
        #expect((a.x < primary.frame.midX) != (b.x < primary.frame.midX))
    }

    @Test func enterStartsAtFromAndEndsAtAnchor() {
        let p = plan()
        let t = MotionTrack.make(spec: MotionSpec(type: .enter, from: "top_offscreen", to: "anchor"), duration: 2,
                                 current: .zero, plan: p, scale: 1, rng: SeededRandom(seed: 1))
        #expect(t.position(at: 0) == p.resolve("top_offscreen", current: .zero))
        #expect(t.position(at: 2) == p.anchor)
        #expect(t.position(at: 99) == p.anchor)
    }

    @Test func offsetIsAppliedToTargetInScaledPixels() {
        let p = plan()
        var spec = MotionSpec(type: .moveTo, to: "anchor")
        spec.offset = [0, 50]
        let t = MotionTrack.make(spec: spec, duration: 1, current: p.anchor, plan: p, scale: 2, rng: SeededRandom(seed: 1))
        #expect(t.end == CGPoint(x: p.anchor.x, y: p.anchor.y + 100))
    }

    @Test func hopReturnsToStartAndPeaksAtHeight() {
        let p = plan()
        var spec = MotionSpec(type: .hop)
        spec.height = 30
        let t = MotionTrack.make(spec: spec, duration: 1, current: p.anchor, plan: p, scale: 1, rng: SeededRandom(seed: 1))
        #expect(t.position(at: 0) == p.anchor)
        #expect(t.position(at: 1) == p.anchor)
        #expect(abs(t.position(at: 0.5).y - (p.anchor.y + 30)) < 0.001)
    }

    @Test func walkHeadsTowardCenterAndStaysOnScreen() {
        let p = plan()
        let left = CGPoint(x: primary.visibleFrame.minX + 60, y: primary.visibleFrame.minY)
        var spec = MotionSpec(type: .walk)
        spec.distance = 5000
        let t = MotionTrack.make(spec: spec, duration: 3, current: left, plan: p, scale: 1, rng: SeededRandom(seed: 1))
        #expect(t.horizontalDirection == .right)
        #expect(t.end.x + box.sprite.right <= primary.visibleFrame.maxX)
        #expect(t.end.y == left.y)
    }

    @Test func dropDefaultsToGround() {
        let p = plan()
        let start = CGPoint(x: 700, y: 400)
        let t = MotionTrack.make(spec: MotionSpec(type: .drop), duration: 0.5, current: start, plan: p, scale: 1, rng: SeededRandom(seed: 1))
        #expect(t.end == CGPoint(x: 700, y: primary.visibleFrame.minY))
    }

    @Test func hoverIsContinuousAtStepBoundaries() {
        let p = plan()
        let t = MotionTrack.make(spec: MotionSpec(type: .hover), duration: 2, current: p.anchor, plan: p, scale: 1, rng: SeededRandom(seed: 1))
        #expect(t.position(at: 0) == p.anchor)
        #expect(abs(t.position(at: 2).y - p.anchor.y) < 0.0001)
    }

    @Test func unimplementedMotionHoldsStill() {
        let p = plan()
        let t = MotionTrack.make(spec: MotionSpec(type: "tether_drop"), duration: 1, current: p.anchor, plan: p, scale: 1, rng: SeededRandom(seed: 1))
        #expect(t.position(at: 0.5) == p.anchor)
    }

    @Test func facingRules() {
        let p = plan()
        let moveRight = MotionTrack(type: .moveTo, start: .init(x: 100, y: 0), end: .init(x: 400, y: 0), duration: 1, curve: .linear)
        #expect(MotionTrack.facing(rule: nil, track: moveRight, current: .left, plan: p) == .right)
        #expect(MotionTrack.facing(rule: "keep", track: moveRight, current: .left, plan: p) == .left)
        let still = MotionTrack(type: .none, start: .init(x: 100, y: 0), end: .init(x: 100, y: 0), duration: 1, curve: .linear)
        #expect(MotionTrack.facing(rule: nil, track: still, current: .left, plan: p) == .left)
        #expect(MotionTrack.facing(rule: "toward_center", track: still, current: .left, plan: p) == .right)
    }

    @Test(arguments: [Easing.linear, .easeIn, .easeOut, .easeInOut])
    func easingEndpoints(_ e: Easing) {
        #expect(e.apply(0) == 0)
        #expect(e.apply(1) == 1)
        #expect(e.apply(-1) == 0)
        #expect(e.apply(2) == 1)
    }
}

// Two displays side by side (primary + one to its right), one far away with a gap, one stacked above.
let rightOf = DisplayGeometry(id: 3, frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080),
                              visibleFrame: CGRect(x: 1440, y: 0, width: 1920, height: 1055), backingScale: 1)
let gapped = DisplayGeometry(id: 4, frame: CGRect(x: 1700, y: 400, width: 800, height: 600),
                             visibleFrame: CGRect(x: 1700, y: 400, width: 800, height: 600), backingScale: 1)

@Suite struct DisplayGraphTests {
    @Test func sideBySideDisplaysAreNeighbours() {
        let g = DisplayGraph([primary, rightOf])
        #expect(g.neighbors(of: 1).map(\.direction) == [.right])
        #expect(g.neighbors(of: 3).map(\.direction) == [.left])
        #expect(g.neighbors(of: 1).first?.overlap == 900)
        #expect(g.next(from: 1, heading: .right)?.continuous == true)
        #expect(g.next(from: 1, heading: .left) == nil)
    }

    @Test func stackedDisplaysAreAboveAndBelow() {
        let g = DisplayGraph([primary, upper])
        #expect(g.neighbors(of: 1).map(\.direction) == [.above])
        #expect(g.neighbors(of: 2).map(\.direction) == [.below])
    }

    @Test func aGapMeansAFadeHop() {
        let g = DisplayGraph([primary, gapped])
        #expect(g.links.isEmpty)
        let n = g.next(from: 1, heading: .right)
        #expect(n?.display.id == 4)
        #expect(n?.continuous == false)
    }
}

@Suite struct CrossDisplayAndClingTests {
    let box = PetBox.make(extents: SpriteExtents(left: 30, right: 30, up: 100, down: 0), scale: 1,
                          padding: .init(side: 20, top: 20, bottom: 40))

    func plan(_ displays: [DisplayGeometry], region: SceneRegion = .air) -> ScenePlan {
        var p = ScenePlanner.plan(region: region, display: primary, box: box, rng: SeededRandom(seed: 2))
        p.allDisplays = displays
        return p
    }

    @Test func continuousFlightEndsPastTheNeighbour() {
        let p = plan([primary, rightOf])
        let t = MotionTrack.make(spec: MotionSpec(type: .crossDisplay), duration: 6, current: CGPoint(x: 300, y: 500), plan: p,
                                 scale: 1, rng: SeededRandom(seed: 1), heading: .right)
        #expect(t.hop == nil)
        #expect(t.end.x > rightOf.frame.maxX)
        #expect(t.opacity(at: 3) == 1)
    }

    @Test func gappedFlightHopsWithAFade() {
        let p = plan([primary, gapped])
        let t = MotionTrack.make(spec: MotionSpec(type: .crossDisplay), duration: 6, current: CGPoint(x: 300, y: 500), plan: p,
                                 scale: 1, rng: SeededRandom(seed: 1), heading: .right)
        let h = t.hop!
        #expect(h.exit.x > primary.frame.maxX && h.entry.x < gapped.frame.minX)
        #expect(t.end.x > gapped.frame.maxX)
        #expect(t.end.y >= gapped.visibleFrame.minY && t.end.y <= gapped.visibleFrame.maxY)
        // Invisible right at the hop, fully visible away from it.
        #expect(t.opacity(at: 6 * h.at) < 0.05)
        #expect(t.opacity(at: 0) == 1 && t.opacity(at: 6) == 1)
    }

    @Test func clingRotatesFeetOntoTheWallAndClimbsHeadFirst() {
        var p = plan([primary], region: .sideEdge)
        p.side = .left
        let up = MotionTrack.make(spec: MotionSpec(type: .cling, from: "wall_below", to: "wall"), duration: 2, current: .zero,
                                  plan: p, scale: 1, rng: SeededRandom(seed: 1))
        #expect(up.fixedRotation == -.pi / 2)
        #expect(up.start.x == primary.visibleFrame.minX && up.end.x == primary.visibleFrame.minX)
        #expect(up.preferredFacing == .left)
        #expect(up.rotates && up.rotation(at: 1) == -.pi / 2)
        p.side = .right
        let down = MotionTrack.make(spec: MotionSpec(type: .cling, from: "wall_high", to: "wall"), duration: 2, current: .zero,
                                    plan: p, scale: 1, rng: SeededRandom(seed: 1))
        #expect(down.fixedRotation == .pi / 2)
        #expect(down.preferredFacing == .left) // right wall, going down
    }
}

@Suite struct SwingAndExitTests {
    let box = PetBox.make(extents: SpriteExtents(left: 30, right: 30, up: 100, down: 0), scale: 1,
                          padding: .init(side: 20, top: 20, bottom: 40))

    @Test func sideExitsLeaveAtTheCurrentHeight() {
        let p = ScenePlan(display: primary, box: box, anchor: CGPoint(x: 1400, y: 500), side: .right)
        let here = CGPoint(x: 700, y: primary.visibleFrame.minY)
        #expect(p.resolve("opposite_offscreen", current: here)?.y == here.y)
        #expect(p.resolve("side_offscreen", current: here)?.y == here.y)
    }

    @Test func aSwingFromTheGroundStaysAboveItAndOnScreen() {
        let v = primary.visibleFrame
        let start = CGPoint(x: 1000, y: v.minY + 60)
        let p = ScenePlan(display: primary, box: box, anchor: start, side: .right)
        var spec = MotionSpec(type: .swing, to: "left_offscreen")
        spec.sweep = 80
        spec.attach = "top"
        let t = MotionTrack.make(spec: spec, duration: 1.6, current: start, plan: p, scale: 1, rng: SeededRandom(seed: 1))
        for i in 0...40 {
            let q = t.position(at: 1.6 * Double(i) / 40)
            #expect(q.y >= v.minY - 0.5, "dips below the ground at \(i)")
            #expect(q.x >= v.minX && q.x <= v.maxX, "leaves the screen at \(i)")
        }
    }
}
