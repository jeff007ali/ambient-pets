import CoreGraphics
import Foundation
import Testing
@testable import PetCore

@Suite struct ClassifierTruthTableTests {
    struct Row: Sendable, CustomStringConvertible {
        var locked = false, presenting = false, meeting = false, gaming = false, fullScreen = false
        var idle = 0.0, reading = false, sinceKey = 999.0
        var expected: ContextState
        var description: String { "\(expected)" }
    }

    static let rows: [Row] = [
        Row(expected: .activeWork),
        Row(idle: 500, expected: .idle),
        Row(reading: true, sinceKey: 5, expected: .activeWork),       // typing in a browser = working
        Row(reading: true, sinceKey: 45, expected: .reading),         // scrolling a page, not typing
        Row(idle: 500, reading: true, expected: .idle),               // away from the desk beats reading
        Row(fullScreen: true, idle: 500, expected: .fullScreen),
        Row(gaming: true, fullScreen: true, expected: .gaming),
        Row(meeting: true, gaming: true, expected: .videoCall),
        Row(presenting: true, meeting: true, expected: .presentation),
        Row(locked: true, presenting: true, meeting: true, expected: .locked),
    ]

    @Test(arguments: rows)
    func classify(_ r: Row) {
        var s = ContextSignals(idleSeconds: r.idle, isLocked: r.locked)
        s.isPresenting = r.presenting
        s.inMeeting = r.meeting
        s.isGaming = r.gaming
        s.frontmostIsFullScreen = r.fullScreen
        s.frontmostIsReadingApp = r.reading
        s.secondsSinceKeystroke = r.sinceKey
        #expect(ContextClassifier.classify(s, idleThreshold: 120) == r.expected)
    }
}

@Suite struct PolicyOverrideTests {
    @Test func perStateFrequencyOverride() {
        var s = AppSettings()
        s.contextFrequency = ["ACTIVE_WORK": 0.2, "VIDEO_CALL": 5]
        #expect(PolicyTable.policy(for: .activeWork, settings: s).frequencyMultiplier == 0.2)
        #expect(PolicyTable.policy(for: .videoCall, settings: s).paused) // an override never un-pauses
        #expect(PolicyTable.policy(for: .idle, settings: s).frequencyMultiplier == 1.5)
    }

    @Test func soundRules() {
        var s = AppSettings()
        s.soundsEnabled = true
        s.soundsOnlyWhenIdle = true
        #expect(PolicyTable.policy(for: .idle, settings: s).audioAllowed)
        #expect(!PolicyTable.policy(for: .activeWork, settings: s).audioAllowed)
        s.soundsOnlyWhenIdle = false
        s.pauseDuringMeetings = false
        #expect(!PolicyTable.policy(for: .videoCall, settings: s).audioAllowed) // muted in meetings by default
    }

    @Test func busyContextsPreferEdgeScenes() {
        let pet = SelectablePet(id: "p", scenes: [
            SceneDefinition(id: "edge", tier: .quick, region: .sideEdge, steps: [StepDefinition(clip: "idle", duration: 3)]),
            SceneDefinition(id: "air", tier: .quick, region: .air, steps: [StepDefinition(clip: "idle", duration: 3)]),
        ])
        let ctx = SelectionContext(state: .reading, policy: PolicyTable.defaultPolicy(for: .reading), now: Date())
        let rng = SeededRandom(seed: 4)
        var edge = 0
        for _ in 0..<4000 where SceneSelector().select(pets: [pet], context: ctx, history: EventHistory(), rng: rng)?.sceneID == "edge" {
            edge += 1
        }
        // 1 : 0.35 → ~74 % edge
        #expect(abs(Double(edge) / 4000 - 1 / 1.35) < 0.03)
    }
}

@Suite struct SafeRegionPlannerTests {
    let box = PetBox.make(extents: SpriteExtents(left: 30, right: 30, up: 100, down: 0), scale: 1,
                          padding: .init(side: 20, top: 20, bottom: 40))

    @Test func noObstaclesBehavesLikeThePlainPlanner() {
        let r = SafeRegionPlanner.plan(region: .bottomEdge, display: primary, box: box, rng: SeededRandom(seed: 1), obstacles: [])
        #expect(r?.score == 0)
        #expect(r?.candidates.count == 1)
    }

    @Test func neverRestsOnTheCaret() {
        // Caret block covering the left two thirds of the bottom strip.
        let caret = Obstacle(rect: CGRect(x: 0, y: 0, width: 960, height: 300), kind: .caret)
        for seed in 0..<30 {
            guard let r = SafeRegionPlanner.plan(region: .bottomEdge, display: primary, box: box, rng: SeededRandom(seed: UInt64(seed)),
                                                 obstacles: [caret], attempts: 20) else { continue }
            let rest = SafeRegionPlanner.restingRect(anchor: r.plan.anchor, box: box)
            #expect(!rest.intersects(caret.rect))
        }
    }

    @Test func allBlockedMeansSkip() {
        let video = Obstacle(rect: primary.frame, kind: .video)
        #expect(SafeRegionPlanner.plan(region: .bottomEdge, display: primary, box: box, rng: SeededRandom(seed: 1), obstacles: [video]) == nil)
    }

    @Test func softObstaclesArePenalisedNotForbidden() {
        let window = Obstacle(rect: primary.frame, kind: .activeWindow)
        let r = SafeRegionPlanner.plan(region: .bottomEdge, display: primary, box: box, rng: SeededRandom(seed: 1), obstacles: [window])
        #expect(r != nil)
        #expect((r?.score ?? 0) > 0)
    }

    @Test func scoreIsOverlapWeighted() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let half = Obstacle(rect: CGRect(x: 50, y: 0, width: 100, height: 100), kind: .cursor)
        #expect(SafeRegionPlanner.score(rect, obstacles: [half]) == 2) // 4 × 0.5
        #expect(SafeRegionPlanner.score(rect, obstacles: [Obstacle(rect: rect, kind: .caret)]) == nil)
    }
}
