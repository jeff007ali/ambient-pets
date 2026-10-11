import CoreGraphics
import Foundation

/// A scene for several pets at once (M7): roles on a shared timeline, placed around a meeting point.
public struct EnsembleScene: Codable, Sendable, Hashable, Identifiable {
    public var formatVersion: Int?
    public var id: String
    public var name: String
    public var tier: SceneTier
    public var weight: Double
    public var cooldownMinutes: Double
    public var allowedContexts: [String]
    public var roles: [EnsembleRole]

    enum CodingKeys: String, CodingKey { case formatVersion, id, name, tier, weight, cooldownMinutes, allowedContexts, roles }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try c.decodeIfPresent(Int.self, forKey: .formatVersion)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(.name, default: id)
        tier = try c.decode(.tier, default: .rare)
        weight = try c.decode(.weight, default: 1)
        cooldownMinutes = try c.decode(.cooldownMinutes, default: 60)
        allowedContexts = try c.decode(.allowedContexts, default: [])
        roles = try c.decode([EnsembleRole].self, forKey: .roles)
    }

    public init(id: String, tier: SceneTier = .rare, roles: [EnsembleRole]) {
        self.id = id
        name = id
        self.tier = tier
        weight = 1
        cooldownMinutes = 0
        allowedContexts = []
        self.roles = roles
    }

    /// History key: ensembles share one cooldown regardless of who played them.
    public var historyKey: String { EventHistory.key(pet: "_ensemble", scene: id) }

    /// The single-pet scene a role plays (its steps), so the normal director can run it.
    public func scene(for role: EnsembleRole) -> SceneDefinition {
        var s = SceneDefinition(id: "\(id).\(role.id)", tier: tier, region: .bottomEdge, steps: role.steps)
        s.name = name
        return s
    }

    /// Assignments of pets to roles that satisfy every role's capabilities (each pet used once).
    public func assignments(for pets: [SelectablePet]) -> [[String: String]] {
        var out: [[String: String]] = []
        func go(_ i: Int, _ used: Set<String>, _ acc: [String: String]) {
            guard i < roles.count else { out.append(acc); return }
            for p in pets where !used.contains(p.id) && roles[i].accepts(p) {
                var next = acc
                next[roles[i].id] = p.id
                go(i + 1, used.union([p.id]), next)
            }
        }
        go(0, [], [:])
        return out
    }
}

public struct EnsembleRole: Codable, Sendable, Hashable {
    public var id: String
    /// Capabilities the pet must have.
    public var requires: [String]
    /// Which side of the meeting point this role stands on.
    public var position: HorizontalSideName
    /// The screen side the role enters from (default: its position side).
    public var enters: HorizontalSideName?
    public var steps: [StepDefinition]

    enum CodingKeys: String, CodingKey { case id, requires, position, enters, steps }

    public init(id: String, requires: [String] = [], position: HorizontalSideName, steps: [StepDefinition]) {
        self.id = id
        self.requires = requires
        self.position = position
        self.steps = steps
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        requires = try c.decode(.requires, default: [])
        position = try c.decode(.position, default: .left)
        enters = try c.decodeIfPresent(HorizontalSideName.self, forKey: .enters)
        steps = try c.decode([StepDefinition].self, forKey: .steps)
    }

    public func accepts(_ pet: SelectablePet) -> Bool { requires.allSatisfy { pet.capabilities[$0] ?? false } }
}

public enum HorizontalSideName: String, Codable, Sendable, Hashable {
    case left, right
    public var side: HorizontalSide { self == .left ? .left : .right }
}

/// Places ensemble roles around one meeting point on the bottom edge.
public enum EnsemblePlanner {
    /// - Parameter boxes: each role's window box, keyed by role id.
    /// - Returns: per role, the anchor (feet) and the entry side.
    public static func place(_ ensemble: EnsembleScene, display: DisplayGeometry, boxes: [String: PetBox],
                             rng: RandomSource) -> [String: (anchor: CGPoint, side: HorizontalSide)] {
        let v = display.visibleFrame
        let meet = rng.double(in: (v.minX + v.width * 0.35)...(v.maxX - v.width * 0.35))
        var out: [String: (CGPoint, HorizontalSide)] = [:]
        // Roles on the same side line up outward from the meeting point.
        var used: [HorizontalSide: Double] = [.left: 0, .right: 0]
        for role in ensemble.roles {
            let side = role.position.side
            let half = boxes[role.id].map { max($0.sprite.left, $0.sprite.right) } ?? 40
            let distance = (used[side] ?? 0) + half + 18
            used[side] = distance + half
            let x = side == .left ? meet - distance : meet + distance
            out[role.id] = (CGPoint(x: min(max(x, v.minX + half), v.maxX - half), y: v.minY), (role.enters ?? role.position).side)
        }
        return out
    }

    /// "b:2" → (role "b", step 2), "b:end" → (role "b", Int.max).
    public static func parseWait(_ s: String) -> (role: String, step: Int)? {
        let parts = s.split(separator: ":").map(String.init)
        guard parts.count == 2 else { return nil }
        if parts[1] == "end" { return (parts[0], Int.max) }
        return Int(parts[1]).map { (parts[0], $0) }
    }
}
