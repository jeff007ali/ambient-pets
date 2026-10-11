import Foundation

/// `blocks.json`: building blocks an AI may compose into a short new routine (M8+). Every block is ordinary scene
/// steps, so a composed routine is validated and played like any authored scene.
public struct RoutineLibrary: Codable, Sendable, Hashable {
    /// How this pet arrives (ends standing at the anchor on the bottom edge).
    public var enter: [StepDefinition]
    /// How it leaves (from wherever it is).
    public var exit: [StepDefinition]
    public var blocks: [String: RoutineBlock]

    public init(enter: [StepDefinition], exit: [StepDefinition], blocks: [String: RoutineBlock]) {
        self.enter = enter
        self.exit = exit
        self.blocks = blocks
    }
}

public struct RoutineBlock: Codable, Sendable, Hashable {
    /// One line for the AI ("fires a repulsor bolt toward the screen centre").
    public var description: String
    /// Steps that start and end standing on the ground near where they began.
    public var steps: [StepDefinition]
}

public enum RoutineComposer {
    public static let minBlocks = 2
    public static let maxBlocks = 5

    /// Builds a scene from block names (unknown names dropped, length clamped to fit the 3–30 s rule), or nil when
    /// fewer than `minBlocks` usable blocks remain. `speechChance` attaches a bubble slot the AI's line can fill.
    public static func compose(_ library: RoutineLibrary, petID: String, blocks names: [String],
                               speechChance: Double = 0.6) -> SceneDefinition? {
        let prefix = "\(petID)."
        var chosen = names.map { $0.hasPrefix(prefix) ? String($0.dropFirst(prefix.count)) : $0 }
            .compactMap { library.blocks[$0] }
        chosen = Array(chosen.prefix(maxBlocks))
        guard chosen.count >= minBlocks else { return nil }
        let frame = library.enter + library.exit
        let budget = PackValidator.sceneDurationRange.upperBound - 2 - frame.reduce(0) { $0 + $1.duration }
        var middle: [StepDefinition] = []
        var used = 0.0
        for block in chosen {
            let d = block.steps.reduce(0) { $0 + $1.duration }
            if used + d > budget { break }
            middle += block.steps
            used += d
        }
        guard !middle.isEmpty, chosen.count >= minBlocks || middle.count >= 2 else { return nil }
        // A bubble slot on the first block step; the AI's line fills it when the chance roll passes.
        if middle[0].speech == nil { middle[0].speech = SpeechSpec(pool: nil, text: nil, chance: speechChance) }
        var scene = SceneDefinition(id: "routine", tier: .funny, tags: ["ai"], region: .bottomEdge, steps: library.enter + middle + library.exit)
        scene.name = "AI Routine"
        guard PackValidator.sceneDurationRange.contains(scene.totalDuration) else { return nil }
        return scene
    }

    /// Block names qualified by pet ("ironman.repulsor_shot"), sorted.
    public static func qualifiedNames(_ library: RoutineLibrary, petID: String) -> [String] {
        library.blocks.keys.sorted().map { "\(petID).\($0)" }
    }
}
