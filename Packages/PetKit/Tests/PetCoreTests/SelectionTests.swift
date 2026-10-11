import Foundation
import Testing
@testable import PetCore

func scene(_ id: String, _ tier: SceneTier, cooldown: Double = 0, contexts: [String] = [],
           minDisplays: Int? = nil, weight: Double = 1, tags: [String] = []) -> SceneDefinition {
    var s = SceneDefinition(id: id, tier: tier, weight: weight, tags: tags, cooldownMinutes: cooldown,
                            allowedContexts: contexts, steps: [StepDefinition(clip: "idle", duration: 3)])
    if let minDisplays { s.requires = SceneRequirements(minDisplays: minDisplays) }
    return s
}

@Suite struct SceneSelectorTests {
    let selector = SceneSelector()
    let now = date(2026, 6, 10, 14)

    var allTiers: SelectablePet {
        SelectablePet(id: "ironman", scenes: [
            scene("q1", .quick), scene("q2", .quick), scene("q3", .quick),
            scene("f1", .funny), scene("f2", .funny),
            scene("e1", .elaborate), scene("e2", .elaborate),
            scene("r1", .rare), scene("r2", .rare),
        ])
    }

    func context(_ state: ContextState = .idle, displays: Int = 1) -> SelectionContext {
        SelectionContext(state: state, policy: PolicyTable.defaultPolicy(for: state), displayCount: displays, now: now)
    }

    @Test func tierDistributionMatchesWeights() {
        let rng = SeededRandom(seed: 2026)
        var counts: [SceneTier: Int] = [:]
        let n = 10_000
        for _ in 0..<n {
            let pick = selector.select(pets: [allTiers], context: context(), history: EventHistory(), rng: rng)!
            counts[pick.tier, default: 0] += 1
        }
        for tier in SceneTier.allCases {
            let share = Double(counts[tier] ?? 0) / Double(n) * 100
            #expect(abs(share - tier.baseWeight) <= 2, "\(tier): \(share)%")
        }
    }

    @Test func missingTiersRenormalise() {
        let pet = SelectablePet(id: "p", scenes: [scene("q", .quick), scene("e", .elaborate)])
        let rng = SeededRandom(seed: 9)
        var elaborate = 0
        for _ in 0..<10_000 where selector.select(pets: [pet], context: context(), history: EventHistory(), rng: rng)!.tier == .elaborate {
            elaborate += 1
        }
        // 10 / (60 + 10) ≈ 14.3 %
        #expect(abs(Double(elaborate) / 100 - 14.3) < 2)
    }

    @Test func noImmediateRepeats() {
        let rng = SeededRandom(seed: 5)
        var history = EventHistory()
        var t = now
        for _ in 0..<1_000 {
            let pick = selector.select(pets: [allTiers], context: SelectionContext(state: .idle, policy: PolicyTable.defaultPolicy(for: .idle), now: t),
                                       history: history, rng: rng)!
            if let last = history.lastEvent { #expect(last.sceneID != pick.sceneID) }
            history.record(AppearanceEvent(date: t, petID: pick.petID, sceneID: pick.sceneID, tier: pick.tier))
            t += 49 * 3600 // past every cooldown
        }
    }

    @Test func onlyCandidateMayRepeat() {
        let pet = SelectablePet(id: "p", scenes: [scene("only", .quick)])
        var h = EventHistory()
        h.record(AppearanceEvent(date: now - 60, petID: "p", sceneID: "only", tier: .quick))
        #expect(selector.select(pets: [pet], context: context(), history: h, rng: SeededRandom(seed: 1))?.sceneID == "only")
    }

    @Test func sceneCooldownExcludes() {
        let pet = SelectablePet(id: "p", scenes: [scene("cool", .quick, cooldown: 60), scene("other", .quick)])
        var h = EventHistory()
        h.record(AppearanceEvent(date: now - 10 * 60, petID: "p", sceneID: "cool", tier: .quick))
        h.record(AppearanceEvent(date: now - 5 * 60, petID: "p", sceneID: "other", tier: .quick))
        #expect(selector.eligible(pets: [pet], context: context(), history: h).map(\.scene.id) == ["other"])

        var later = context()
        later.now = now + 51 * 60 // 61 min after "cool"
        #expect(Set(selector.eligible(pets: [pet], context: later, history: h).map(\.scene.id)) == ["cool"]) // "other" was last
    }

    @Test func rareScenesHaveIndependentLongCooldown() {
        let pet = SelectablePet(id: "p", scenes: [scene("r", .rare), scene("q", .quick), scene("q2", .quick)])
        var h = EventHistory()
        h.record(AppearanceEvent(date: now - 24 * 3600, petID: "p", sceneID: "r", tier: .rare))
        h.record(AppearanceEvent(date: now - 60, petID: "p", sceneID: "q2", tier: .quick))
        #expect(!selector.eligible(pets: [pet], context: context(), history: h).contains { $0.scene.id == "r" })
        var later = context()
        later.now = now + 25 * 3600
        #expect(selector.eligible(pets: [pet], context: later, history: h).contains { $0.scene.id == "r" })
    }

    @Test func contextAndPolicyFilter() {
        let pet = SelectablePet(id: "p", scenes: [
            scene("idleOnly", .quick, contexts: ["IDLE"]), scene("long", .elaborate), scene("short", .quick),
        ])
        let work = selector.eligible(pets: [pet], context: context(.activeWork), history: EventHistory()).map(\.scene.id)
        #expect(work == ["short"]) // elaborate not allowed while working; idleOnly filtered by context
        #expect(selector.select(pets: [pet], context: context(.videoCall), history: EventHistory(), rng: SeededRandom(seed: 1)) == nil)
    }

    @Test func userTierToggles() {
        var c = context()
        c.enabledTiers = [.funny]
        let picks = selector.eligible(pets: [allTiers], context: c, history: EventHistory())
        #expect(Set(picks.map(\.scene.tier)) == [.funny])
    }

    @Test func requirementsFilter() {
        let pet = SelectablePet(id: "p", capabilities: ["canFly": true], scenes: [
            scene("cross", .elaborate, minDisplays: 2), scene("solo", .quick),
        ])
        #expect(selector.eligible(pets: [pet], context: context(displays: 1), history: EventHistory()).map(\.scene.id) == ["solo"])
        #expect(selector.eligible(pets: [pet], context: context(displays: 2), history: EventHistory()).count == 2)

        var needsSwing = scene("swing", .quick)
        needsSwing.requires = SceneRequirements(capabilities: ["canSwing"])
        let p2 = SelectablePet(id: "p", capabilities: ["canFly": true], scenes: [needsSwing])
        #expect(selector.eligible(pets: [p2], context: context(), history: EventHistory()).isEmpty)
    }

    @Test func personalityWeightsTags() {
        var shy = Personality()
        shy.friendliness = 0
        #expect(shy.multiplier(forTags: ["greeting"]) == 0.5)
        #expect(shy.multiplier(forTags: ["flashy"]) == 1)
        var friendly = Personality()
        friendly.friendliness = 1
        #expect(friendly.multiplier(forTags: ["greeting"]) == 1.5)
    }

    @Test func recentScenesArePenalisedButStillPossible() {
        let pet = SelectablePet(id: "p", scenes: [scene("a", .quick), scene("b", .quick), scene("c", .quick)])
        var h = EventHistory()
        h.record(AppearanceEvent(date: now - 120, petID: "p", sceneID: "a", tier: .quick))
        h.record(AppearanceEvent(date: now - 60, petID: "p", sceneID: "b", tier: .quick))
        let rng = SeededRandom(seed: 11)
        var counts: [String: Int] = [:]
        for _ in 0..<6_000 { counts[selector.select(pets: [pet], context: context(), history: h, rng: rng)!.sceneID, default: 0] += 1 }
        #expect(counts["b"] == nil) // immediate repeat
        // c : a = 1 : 0.5
        #expect(abs(Double(counts["c"]!) / Double(counts["a"]!) - 2) < 0.15)
    }
}

@Suite struct HistoryTests {
    @Test func capKeepsLastPlayedAndCounts() {
        var h = EventHistory()
        let t0 = date(2026, 1, 1, 9)
        h.record(AppearanceEvent(date: t0, petID: "p", sceneID: "rare", tier: .rare))
        for i in 0..<250 { h.record(AppearanceEvent(date: t0 + Double(i + 1), petID: "p", sceneID: "q", tier: .quick)) }
        #expect(h.events.count == EventHistory.cap)
        #expect(!h.events.contains { $0.sceneID == "rare" })
        #expect(h.lastPlayed(pet: "p", scene: "rare") == t0)
        #expect(h.sceneCounts["p/q"] == 250)
        #expect(h.recentKeys(2) == ["p/q", "p/q"])
    }

    @Test func storeRoundTripsAndToleratesGarbage() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "pets-history-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = HistoryStore(url: dir.appending(path: "history.json"))
        #expect(store.load().events.isEmpty)

        var h = EventHistory()
        h.record(AppearanceEvent(date: Date(timeIntervalSince1970: 1_800_000_000), petID: "p", sceneID: "s", tier: .funny,
                                 displayID: 7, context: .idle))
        try store.save(h)
        #expect(store.load() == h)

        try Data("not json".utf8).write(to: store.url)
        #expect(store.load().events.isEmpty)
    }
}
