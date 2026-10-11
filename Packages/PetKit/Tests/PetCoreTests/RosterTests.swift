import CoreGraphics
import Foundation
import Testing
@testable import PetCore

@Suite struct ScreenLaneTests {
    let box = PetBox.make(extents: SpriteExtents(left: 30, right: 30, up: 100, down: 0), scale: 1,
                          padding: .init(side: 20, top: 20, bottom: 40))

    @Test func lanesSplitTheScreen() {
        let lane = ScreenLane(index: 1, count: 2)
        #expect(lane.slice(of: CGRect(x: 0, y: 0, width: 1000, height: 500)) == CGRect(x: 500, y: 0, width: 500, height: 500))
        #expect(ScreenLane(index: 0, count: 3).edge == .left)
        #expect(ScreenLane(index: 1, count: 3).edge == nil)
        #expect(ScreenLane(index: 2, count: 3).edge == .right)
        #expect(ScreenLane(index: 9, count: 2).index == 1) // clamped
    }

    @Test(arguments: [SceneRegion.bottomEdge, .air, .topEdge, .anywhere])
    func anchorsStayInTheirLane(_ region: SceneRegion) {
        for seed in 0..<40 {
            let rng = SeededRandom(seed: UInt64(seed))
            let left = ScenePlanner.plan(region: region, display: primary, box: box, rng: rng, lane: ScreenLane(index: 0, count: 2))
            let right = ScenePlanner.plan(region: region, display: primary, box: box, rng: rng, lane: ScreenLane(index: 1, count: 2))
            #expect(left.anchor.x <= primary.visibleFrame.midX)
            #expect(right.anchor.x >= primary.visibleFrame.midX)
            #expect(left.side == .left && right.side == .right)
        }
    }

    @Test func sideEdgeUsesTheLanesEdgeAndMiddleLaneFallsBackToBottom() {
        let rng = SeededRandom(seed: 3)
        let right = ScenePlanner.plan(region: .sideEdge, display: primary, box: box, rng: rng, lane: ScreenLane(index: 1, count: 2))
        #expect(right.side == .right && right.anchor.x > primary.visibleFrame.maxX - 40)
        let middle = ScenePlanner.plan(region: .sideEdge, display: primary, box: box, rng: rng, lane: ScreenLane(index: 1, count: 3))
        #expect(middle.anchor.y == primary.visibleFrame.minY)
    }
}

@Suite struct PetRosterTests {
    let ids = ["ironman", "spiderman", "batman"]

    @Test func mixUsesEveryEnabledPet() {
        var s = AppSettings()
        s.disabledPets = ["spiderman"]
        #expect(PetRoster.active(ids, settings: s) == ["ironman", "batman"])
    }

    @Test func singleModeUsesTheChosenPetOrFallsBack() {
        var s = AppSettings()
        s.petMode = .single
        s.singlePetID = "batman"
        #expect(PetRoster.active(ids, settings: s) == ["batman"])
        s.disabledPets = ["batman"]
        #expect(PetRoster.active(ids, settings: s) == ["ironman"])
        s.singlePetID = nil
        s.disabledPets = []
        #expect(PetRoster.active(ids, settings: s) == ["ironman"])
    }

    @Test func allDisabledMeansNobody() {
        var s = AppSettings()
        s.disabledPets = Set(ids)
        #expect(PetRoster.active(ids, settings: s).isEmpty)
    }

    @Test func groupSizeHonoursChanceModeAndCap() {
        var s = AppSettings()
        s.togetherChance = 0
        #expect(PetRoster.groupSize(available: 3, settings: s, rng: SeededRandom(seed: 1)) == 1)
        s.togetherChance = 1
        s.maxTogether = 3
        let rng = SeededRandom(seed: 2)
        let sizes = Set((0..<200).map { _ in PetRoster.groupSize(available: 3, settings: s, rng: rng) })
        #expect(sizes == [2, 3])
        #expect(PetRoster.groupSize(available: 1, settings: s, rng: rng) == 1)
        s.petMode = .single
        #expect(PetRoster.groupSize(available: 3, settings: s, rng: rng) == 1)
    }

    @Test func togetherChanceIsRoughlyRight() {
        var s = AppSettings()
        s.togetherChance = 0.25
        let rng = SeededRandom(seed: 77)
        let groups = (0..<10_000).filter { _ in PetRoster.groupSize(available: 2, settings: s, rng: rng) > 1 }.count
        #expect(abs(Double(groups) / 10_000 - 0.25) < 0.02)
    }

    @Test func petSettingsSurviveRoundTrip() throws {
        var s = AppSettings()
        s.petMode = .single
        s.singlePetID = "spiderman"
        s.disabledPets = ["batman"]
        s.maxTogether = 3
        #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s)) == s)
    }
}

@Suite struct ProjectileValidationTests {
    @Test func projectileClipsMustExist() throws {
        let def = try decode(PetDefinition.self, #"{"id": "t"}"#)
        let atlas = SpriteAtlas(image: "s.png", frames: ["i0": AtlasFrame(rect: CGRect(x: 0, y: 0, width: 8, height: 8), pivot: CGPoint(x: 4, y: 8))])
        var step = StepDefinition(clip: "idle", duration: 3, effects: [EffectSpec("projectile", params: ["clip": .string("nope")]), EffectSpec("projectile")])
        step.motion = .none
        let pack = PetPackData(directory: URL(fileURLWithPath: "/x"), definition: def, atlas: atlas,
                               clips: ClipLibrary(["idle": ClipDefinition(frames: ["i0"])]),
                               scenes: [SceneDefinition(id: "s", tier: .quick, steps: [step])], lines: [:])
        let msgs = PackValidator.validate(pack, imageSize: CGSize(width: 8, height: 8)).map(\.message)
        #expect(msgs.contains { $0.contains("projectile clip: clip 'nope' is not defined") })
        #expect(msgs.contains { $0.contains("projectile needs a 'clip'") })
    }
}

@Suite struct SwingAndScaleTests {
    let box = PetBox.make(extents: SpriteExtents(left: 30, right: 30, up: 100, down: 0), scale: 1,
                          padding: .init(side: 20, top: 20, bottom: 40))

    @Test func swingIsAPendulumTowardsItsTarget() {
        let plan = ScenePlanner.plan(region: .air, display: primary, box: box, rng: SeededRandom(seed: 1))
        var spec = MotionSpec(type: .swing, to: "right_offscreen")
        spec.radius = 200
        spec.sweep = 90
        let start = CGPoint(x: 300, y: 600)
        let t = MotionTrack.make(spec: spec, duration: 2, current: start, plan: plan, scale: 1, rng: SeededRandom(seed: 1))
        let p = t.pendulum!
        // Starts at the start point, ends level with it 2·r·sin(45°) further right.
        #expect(abs(t.position(at: 0).x - start.x) < 1e-9 && abs(t.position(at: 0).y - start.y) < 1e-9)
        #expect(abs(t.end.x - (start.x + 2 * 200 * sin(Double.pi / 4))) < 1e-6)
        #expect(abs(t.end.y - start.y) < 1e-6)
        // Every point stays on the circle; the lowest point is straight under the anchor, mid-swing.
        for e in stride(from: 0.0, through: 2.0, by: 0.25) {
            let q = t.position(at: e)
            #expect(abs(hypot(q.x - p.center.x, q.y - p.center.y) - 200) < 1e-6)
        }
        #expect(abs(t.position(at: 1).x - p.center.x) < 1e-6)
        #expect(abs(t.rotation(at: 1)) < 1e-9)
        // Rotation leans the body towards the anchor: negative (clockwise) at the start of a rightward swing.
        #expect(t.rotation(at: 0) < 0 && t.rotation(at: 2) > 0)
        #expect(t.horizontalDirection == .right)
    }

    @Test func swingWithoutTargetFollowsHeading() {
        let plan = ScenePlanner.plan(region: .air, display: primary, box: box, rng: SeededRandom(seed: 1))
        let t = MotionTrack.make(spec: MotionSpec(type: .swing), duration: 1, current: CGPoint(x: 800, y: 600), plan: plan,
                                 scale: 1, rng: SeededRandom(seed: 1), heading: .left)
        #expect(t.horizontalDirection == .left)
    }

    @Test func advanceMovesAlongHeading() {
        let plan = ScenePlanner.plan(region: .air, display: primary, box: box, rng: SeededRandom(seed: 1))
        var spec = MotionSpec(type: .arc)
        spec.advance = [100, 10]
        let t = MotionTrack.make(spec: spec, duration: 1, current: CGPoint(x: 500, y: 500), plan: plan, scale: 2,
                                 rng: SeededRandom(seed: 1), heading: .left)
        #expect(t.end == CGPoint(x: 300, y: 520))
    }

    @Test func petsWithAHeightAllRenderAtTheSameHeight() throws {
        let iron = try decode(PetDefinition.self, #"{"id": "a", "height": 40}"#)
        let spidey = try decode(PetDefinition.self, #"{"id": "b", "height": 68}"#)
        let legacy = try decode(PetDefinition.self, #"{"id": "c", "defaultScale": 2}"#)
        #expect(abs(iron.renderScale(userScale: 0.8) * 40 - spidey.renderScale(userScale: 0.8) * 68) < 1e-9)
        #expect(abs(iron.renderScale(userScale: 1) * 40 - PetDefinition.standardHeight) < 1e-9)
        #expect(legacy.renderScale(userScale: 0.5) == 1)
        #expect(iron.renderScale(userScale: 9) == iron.renderScale(userScale: 1.5)) // clamped
    }
}

@Suite struct TopAttachedSwingTests {
    @Test func anchorSitsOnTheScreensTopEdge() {
        let box = PetBox.make(extents: SpriteExtents(left: 30, right: 30, up: 100, down: 0), scale: 1,
                              padding: .init(side: 20, top: 20, bottom: 40))
        let plan = ScenePlanner.plan(region: .air, display: primary, box: box, rng: SeededRandom(seed: 1))
        var spec = MotionSpec(type: .swing, to: "right_offscreen")
        spec.attach = "top"
        spec.sweep = 80
        let start = CGPoint(x: 200, y: 500)
        let t = MotionTrack.make(spec: spec, duration: 1.6, current: start, plan: plan, scale: 1, rng: SeededRandom(seed: 1))
        let p = t.pendulum!
        #expect(abs(p.center.y - primary.frame.maxY) < 1e-6)
        #expect(abs(p.radius - (primary.frame.maxY - 500) / cos(40 * Double.pi / 180)) < 1e-6)
        #expect(abs(t.end.y - start.y) < 1e-6) // level swing
    }
}
