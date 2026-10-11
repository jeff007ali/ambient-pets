import Foundation

/// A pet as the selector sees it.
public struct SelectablePet: Sendable {
    public var id: String
    public var weight: Double
    public var personality: Personality
    public var capabilities: [String: Bool]
    public var scenes: [SceneDefinition]

    public init(id: String, weight: Double = 1, personality: Personality = Personality(),
                capabilities: [String: Bool] = [:], scenes: [SceneDefinition]) {
        self.id = id
        self.weight = weight
        self.personality = personality
        self.capabilities = capabilities
        self.scenes = scenes
    }

    public init(_ pack: PetPackData, settings: AppSettings? = nil) {
        let user = settings?.petWeights[pack.id] ?? 1
        self.init(id: pack.id, weight: pack.definition.weight * max(user, 0), personality: pack.definition.personality,
                  capabilities: pack.definition.capabilities, scenes: pack.scenes)
    }
}

public struct SelectionContext: Sendable {
    public var state: ContextState
    public var policy: ContextPolicy
    public var enabledTiers: Set<SceneTier>
    public var displayCount: Int
    public var now: Date

    public init(state: ContextState, policy: ContextPolicy, enabledTiers: Set<SceneTier> = Set(SceneTier.allCases),
                displayCount: Int = 1, now: Date) {
        self.state = state
        self.policy = policy
        self.enabledTiers = enabledTiers
        self.displayCount = displayCount
        self.now = now
    }
}

public struct SceneCandidate: Sendable, Hashable {
    public var petID: String
    public var scene: SceneDefinition
    public var weight: Double

    public init(petID: String, scene: SceneDefinition, weight: Double) {
        self.petID = petID
        self.scene = scene
        self.weight = weight
    }
    public var key: String { EventHistory.key(pet: petID, scene: scene.id) }
}

public struct SceneSelection: Sendable, Hashable {
    public var petID: String
    public var sceneID: String
    public var tier: SceneTier

    public init(petID: String, sceneID: String, tier: SceneTier) {
        self.petID = petID
        self.sceneID = sceneID
        self.tier = tier
    }
}

/// Decides *what* plays (spec §31): filter by context and capability → drop cooldowns → tier roll →
/// weight × personality × anti-repeat → pick.
public struct SceneSelector: Sendable {
    public var tierWeights: [SceneTier: Double] = Dictionary(uniqueKeysWithValues: SceneTier.allCases.map { ($0, $0.baseWeight) })
    /// Each rare scene plays at most once in this window.
    public var rareCooldownHours: Double = 48
    /// Weight multiplier for scenes among the last few appearances.
    public var recentPenalty: Double = 0.5
    public var recentWindow = 5
    /// Weight multiplier for scenes outside the context's preferred regions.
    public var nonPreferredRegionFactor = 0.35

    public init() {}

    /// Candidates that pass every hard filter (context, tier toggles, requirements, cooldowns, no immediate repeat).
    public func eligible(pets: [SelectablePet], context: SelectionContext, history: EventHistory) -> [SceneCandidate] {
        var out: [SceneCandidate] = []
        for pet in pets where pet.weight > 0 {
            for scene in pet.scenes where scene.weight > 0 && !scene.steps.isEmpty {
                guard context.enabledTiers.contains(scene.tier), context.policy.allowedTiers.contains(scene.tier) else { continue }
                if !scene.allowedContexts.isEmpty, !scene.allowedContexts.contains(context.state.rawValue) { continue }
                if let req = scene.requires {
                    if let n = req.minDisplays, context.displayCount < n { continue }
                    if let caps = req.capabilities, !caps.allSatisfy({ pet.capabilities[$0] ?? false }) { continue }
                }
                var cooldown = scene.cooldownMinutes * 60
                if scene.tier == .rare { cooldown = max(cooldown, rareCooldownHours * 3600) }
                if cooldown > 0, let last = history.lastPlayed(pet: pet.id, scene: scene.id),
                   context.now.timeIntervalSince(last) < cooldown { continue }
                var weight = scene.weight * pet.weight * pet.personality.multiplier(forTags: scene.tags)
                // Busy contexts prefer edge scenes (spec §10: "edge animations" while reading / working).
                if !context.policy.preferredRegions.isEmpty, !context.policy.preferredRegions.contains(scene.region) {
                    weight *= nonPreferredRegionFactor
                }
                out.append(SceneCandidate(petID: pet.id, scene: scene, weight: weight))
            }
        }
        // Never the same scene twice in a row, unless it's the only option.
        if out.count > 1, let lastKey = history.lastEvent?.key {
            out.removeAll { $0.key == lastKey }
        }
        return out
    }

    public func select(pets: [SelectablePet], context: SelectionContext, history: EventHistory,
                       rng: RandomSource) -> SceneSelection? {
        let candidates = eligible(pets: pets, context: context, history: history)
        guard !candidates.isEmpty else { return nil }

        // Tier roll among tiers that actually have candidates (weights renormalise automatically).
        let tiers = SceneTier.allCases.filter { t in candidates.contains { $0.scene.tier == t } }
        guard let ti = rng.weightedIndex(tiers.map { tierWeights[$0] ?? 0 }) else { return nil }
        let tier = tiers[ti]

        let pool = candidates.filter { $0.scene.tier == tier }
        let recent = Set(history.recentKeys(recentWindow))
        let weights = pool.map { recent.contains($0.key) ? $0.weight * recentPenalty : $0.weight }
        guard let ci = rng.weightedIndex(weights) else { return nil }
        let pick = pool[ci]
        return SceneSelection(petID: pick.petID, sceneID: pick.scene.id, tier: pick.scene.tier)
    }
}
