import CoreGraphics
import Foundation

public enum SceneTier: String, Codable, Sendable, CaseIterable, Hashable {
    case quick, funny, elaborate, rare

    /// Default tier roll weights (spec §8.2): 60 / 25 / 10 / 5.
    public var baseWeight: Double {
        switch self {
        case .quick: 60
        case .funny: 25
        case .elaborate: 10
        case .rare: 5
        }
    }
}

/// Open string enums: unknown values decode fine and are reported by the validator instead of crashing.
public struct MotionType: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }

    public static let none: MotionType = "none"
    public static let enter: MotionType = "enter"
    public static let exit: MotionType = "exit"
    public static let moveTo: MotionType = "moveTo"
    public static let walk: MotionType = "walk"
    public static let hover: MotionType = "hover"
    public static let hop: MotionType = "hop"
    public static let drop: MotionType = "drop"
    public static let arc: MotionType = "arc"
    /// Pendulum swing on a line (web, grapple): the body rotates to point at the line's anchor.
    public static let swing: MotionType = "swing"
    /// Crawl along a screen side edge, rotated 90° so the feet are on the wall.
    public static let cling: MotionType = "cling"
    /// Travel off this display onto the next one (continuous if adjacent, else fade out / fade in).
    public static let crossDisplay: MotionType = "cross_display"

    /// Implemented by the engine today.
    public static let supported: Set<MotionType> = [.none, .enter, .exit, .moveTo, .walk, .hover, .hop, .drop, .arc, .swing,
                                                    .cling, .crossDisplay]
    /// Part of the format but not implemented yet. They play as `none`. (`tether_drop` is `enter` + `tether_line`.)
    public static let planned: Set<MotionType> = ["path", "tether_drop"]
}

public struct EffectType: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }

    public static let thruster: EffectType = "thruster"
    public static let repulsorFlash: EffectType = "repulsor_flash"
    public static let beam: EffectType = "beam"
    public static let dustPuff: EffectType = "dust_puff"
    public static let squash: EffectType = "squash"
    public static let tilt: EffectType = "tilt"
    public static let fade: EffectType = "fade"
    public static let scanline: EffectType = "scanline"
    public static let zzz: EffectType = "zzz"
    public static let speechBubble: EffectType = "speech_bubble"
    public static let tetherLine: EffectType = "tether_line"
    /// A pack clip fired forward (web ball, batarang, repulsor bolt), optionally ending in a `hit` clip.
    public static let projectile: EffectType = "projectile"
    /// A pack clip attached to a body point, played in place (a beam from the chest, a shockwave, a muzzle flash).
    public static let overlay: EffectType = "overlay"

    public static let supported: Set<EffectType> = [
        .thruster, .repulsorFlash, .beam, .dustPuff, .squash, .tilt, .fade, .scanline, .zzz, .speechBubble, .tetherLine,
        .projectile, .overlay,
    ]
    public static let planned: Set<EffectType> = []
}

public struct SceneRegion: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }

    /// Standing on the bottom of the visible frame (above the Dock).
    public static let bottomEdge: SceneRegion = "bottom_edge"
    /// Partly hidden behind a left or right screen edge.
    public static let sideEdge: SceneRegion = "side_edge"
    /// Just under the menu bar.
    public static let topEdge: SceneRegion = "top_edge"
    /// Somewhere in the upper half, mid-air.
    public static let air: SceneRegion = "air"
    public static let anywhere: SceneRegion = "anywhere"

    public static let known: Set<SceneRegion> = [.bottomEdge, .sideEdge, .topEdge, .air, .anywhere]
}

public enum Easing: String, Codable, Sendable, Hashable {
    case linear, easeIn, easeOut, easeInOut

    public func apply(_ t: Double) -> Double {
        let t = min(max(t, 0), 1)
        switch self {
        case .linear: return t
        case .easeIn: return t * t
        case .easeOut: return 1 - (1 - t) * (1 - t)
        case .easeInOut: return t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
        }
    }
}

public struct MotionSpec: Codable, Sendable, Hashable {
    public var type: MotionType
    /// Anchor reference to start from (teleports there at step start). See `AnchorRef`.
    public var from: String?
    /// Anchor reference to move to.
    public var to: String?
    public var curve: Easing?
    /// hop / arc height, native px.
    public var height: Double?
    /// walk speed, native px per second.
    public var speed: Double?
    /// walk distance, native px (default: speed × duration).
    public var distance: Double?
    /// walk direction: left, right, toward_center, away_from_center, random.
    public var direction: String?
    /// hover bob amplitude, native px.
    public var amplitude: Double?
    /// hover bob frequency, Hz.
    public var frequency: Double?
    /// [dx, dy] added to the `to` point, native px (y up).
    public var offset: [Double]?
    /// Without `to`: move by [dx, dy] native px from the current point, dx along the pet's heading.
    public var advance: [Double]?
    /// swing: line length from the anchor to the feet, native px.
    public var radius: Double?
    /// swing: total angle swept, degrees (centred on straight down).
    public var sweep: Double?
    /// swing: "top" attaches the line to the top edge of the screen (the rope length follows from the height);
    /// otherwise the anchor is `radius` above the low point.
    public var attach: String?

    public init(type: MotionType, from: String? = nil, to: String? = nil, curve: Easing? = nil) {
        self.type = type
        self.from = from
        self.to = to
        self.curve = curve
    }

    public static let none = MotionSpec(type: .none)
}

/// An effect: either `"thruster"` or `{ "type": "thruster", "at": "thruster", … }`.
public struct EffectSpec: Codable, Sendable, Hashable {
    public var type: EffectType
    public var params: [String: JSONValue]

    public init(_ type: EffectType, params: [String: JSONValue] = [:]) {
        self.type = type
        self.params = params
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            type = EffectType(rawValue: s)
            params = [:]
            return
        }
        var object = try c.decode([String: JSONValue].self)
        guard let t = object.removeValue(forKey: "type")?.string else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "effect object needs a string 'type'")
        }
        type = EffectType(rawValue: t)
        params = object
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if params.isEmpty {
            try c.encode(type.rawValue)
        } else {
            var o = params
            o["type"] = .string(type.rawValue)
            try c.encode(o)
        }
    }

    public func double(_ key: String) -> Double? { params[key]?.double }
    public func string(_ key: String) -> String? { params[key]?.string }
    public func bool(_ key: String) -> Bool? { params[key]?.bool }

    /// `[x, y]` literal point, if the param is an array.
    public func point(_ key: String) -> CGPoint? {
        guard let a = params[key]?.array, a.count == 2, let x = a[0].double, let y = a[1].double else { return nil }
        return CGPoint(x: x, y: y)
    }
}

public struct SpeechSpec: Codable, Sendable, Hashable {
    /// Pool name in `lines.json`.
    public var pool: String?
    /// Literal line (used if no pool).
    public var text: String?
    /// Probability the bubble is shown at all. Defaults to 1.
    public var chance: Double?
}

extension StepDefinition {
    /// Standing, hovering or clinging in place: the only moments a pet talks (a moving pet's bubble can't be read).
    public var isStill: Bool {
        switch motion.type {
        case .none, .hover: true
        case .cling: motion.to == "current"
        default: false
        }
    }
}

extension SceneDefinition {
    /// The scene has a still moment where a speech bubble can show.
    public var canSpeak: Bool { steps.contains(where: \.isStill) }
}

public struct StepDefinition: Codable, Sendable, Hashable {
    public var clip: String
    public var motion: MotionSpec
    public var duration: Double
    public var effects: [EffectSpec]
    public var sound: String?
    public var speech: SpeechSpec?
    /// nil = automatic (face the direction of travel). Else left, right, toward_center, away_from_center, keep,
    /// cursor, partner (ensembles).
    public var facing: String?
    /// Ensembles: hold this step until another role reaches a step, e.g. "b:2" (1-based) or "b:end".
    public var waitFor: String?

    enum CodingKeys: String, CodingKey { case clip, motion, duration, effects, sound, speech, facing, waitFor }

    public init(clip: String, motion: MotionSpec = .none, duration: Double, effects: [EffectSpec] = []) {
        self.clip = clip
        self.motion = motion
        self.duration = duration
        self.effects = effects
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clip = try c.decode(String.self, forKey: .clip)
        motion = try c.decode(.motion, default: .none)
        duration = try c.decode(Double.self, forKey: .duration)
        effects = try c.decode(.effects, default: [])
        sound = try c.decodeIfPresent(String.self, forKey: .sound)
        speech = try c.decodeIfPresent(SpeechSpec.self, forKey: .speech)
        facing = try c.decodeIfPresent(String.self, forKey: .facing)
        waitFor = try c.decodeIfPresent(String.self, forKey: .waitFor)
    }
}

public struct SceneRequirements: Codable, Sendable, Hashable {
    public var minDisplays: Int?
    public var capabilities: [String]?
}

/// `scenes/*.json`: an ordered list of steps plus selection metadata.
public struct SceneDefinition: Codable, Sendable, Hashable, Identifiable {
    public var formatVersion: Int?
    public var id: String
    public var name: String
    public var tier: SceneTier
    public var weight: Double
    public var tags: [String]
    /// Minimum minutes between two plays of this scene. Rare scenes also get the selector's rare cooldown.
    public var cooldownMinutes: Double
    /// Empty = any non-paused context.
    public var allowedContexts: [String]
    public var region: SceneRegion
    public var requires: SceneRequirements?
    public var steps: [StepDefinition]

    enum CodingKeys: String, CodingKey {
        case formatVersion, id, name, tier, weight, tags, cooldownMinutes, allowedContexts, region, requires, steps
    }

    public init(id: String, tier: SceneTier, weight: Double = 1, tags: [String] = [], cooldownMinutes: Double = 0,
                allowedContexts: [String] = [], region: SceneRegion = .bottomEdge, steps: [StepDefinition] = []) {
        self.id = id
        self.name = id
        self.tier = tier
        self.weight = weight
        self.tags = tags
        self.cooldownMinutes = cooldownMinutes
        self.allowedContexts = allowedContexts
        self.region = region
        self.steps = steps
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try c.decodeIfPresent(Int.self, forKey: .formatVersion)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(.name, default: id)
        tier = try c.decode(.tier, default: .quick)
        weight = try c.decode(.weight, default: 1)
        tags = try c.decode(.tags, default: [])
        cooldownMinutes = try c.decode(.cooldownMinutes, default: 0)
        allowedContexts = try c.decode(.allowedContexts, default: [])
        region = try c.decode(.region, default: .bottomEdge)
        requires = try c.decodeIfPresent(SceneRequirements.self, forKey: .requires)
        steps = try c.decode(.steps, default: [])
    }

    public var totalDuration: Double { steps.reduce(0) { $0 + $1.duration } }

    /// Every clip id the scene references.
    public var clipIDs: Set<String> { Set(steps.map(\.clip)) }
}
