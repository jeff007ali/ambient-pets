import Foundation

/// Highest pack `formatVersion` this engine understands.
public let supportedFormatVersion = 1

public enum Facing: String, Codable, Sendable, Hashable {
    case left, right

    public var opposite: Facing { self == .left ? .right : .left }
    /// +1 for right, -1 for left.
    public var sign: Double { self == .right ? 1 : -1 }
}

/// `pet.json`: identity, renderer kind, personality, capabilities, sounds.
public struct PetDefinition: Codable, Sendable {
    public var formatVersion: Int
    public var id: String
    public var name: String
    public var version: String?
    public var renderer: String
    /// Multiplies native sprite size, before the user's size slider. Ignored when `height` is set.
    public var defaultScale: Double
    /// Standing height of the character in sprite pixels. When set, every pet is scaled to the same on-screen
    /// height (`standardHeight` points at 100 %), so pets from different games match when they appear together.
    public var height: Double?
    /// Relative weight of this pet when several are enabled.
    public var weight: Double
    public var personality: Personality
    /// e.g. `canFly`, `canWalk`, `cursorTracking`, `multiMonitor`, `audio`.
    public var capabilities: [String: Bool]
    /// Sound name → file path relative to the pack.
    public var sounds: [String: String]

    public func has(_ capability: String) -> Bool { capabilities[capability] ?? false }

    /// On-screen height of a standing pet at 100 % size, points.
    public static let standardHeight = 135.0

    /// Sprite px → points for a given user size (0.5…1.5).
    public func renderScale(userScale: Double) -> Double {
        let user = min(max(userScale, AppSettings.scaleRange.lowerBound), AppSettings.scaleRange.upperBound)
        if let height, height > 0 { return user * Self.standardHeight / height }
        return user * defaultScale
    }

    enum CodingKeys: String, CodingKey {
        case formatVersion, id, name, version, renderer, defaultScale, height, weight, personality, capabilities, sounds
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try c.decode(.formatVersion, default: 1)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(.name, default: id)
        version = try c.decodeIfPresent(String.self, forKey: .version)
        renderer = try c.decode(.renderer, default: "sprite")
        defaultScale = try c.decode(.defaultScale, default: 1.0)
        height = try c.decodeIfPresent(Double.self, forKey: .height)
        weight = try c.decode(.weight, default: 1.0)
        personality = try c.decode(.personality, default: Personality())
        capabilities = try c.decode(.capabilities, default: [:])
        sounds = try c.decode(.sounds, default: [:])
    }
}

/// Personality traits in 0…1 (except `activity`, a frequency factor around 1).
public struct Personality: Codable, Sendable, Hashable {
    public var activity: Double = 1.0
    public var friendliness: Double = 0.5
    public var mischievousness: Double = 0.5
    public var interaction: Double = 0.5
    public var curiosity: Double = 0.5

    public init() {}

    enum CodingKeys: String, CodingKey { case activity, friendliness, mischievousness, interaction, curiosity }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        activity = try c.decode(.activity, default: 1.0)
        friendliness = try c.decode(.friendliness, default: 0.5)
        mischievousness = try c.decode(.mischievousness, default: 0.5)
        interaction = try c.decode(.interaction, default: 0.5)
        curiosity = try c.decode(.curiosity, default: 0.5)
    }

    /// Scene weight multiplier from tags. A trait of 0.5 is neutral (×1); 0 → ×0.5, 1 → ×1.5.
    public func multiplier(forTags tags: [String]) -> Double {
        var m = 1.0
        for tag in tags {
            switch tag {
            case "greeting": m *= 0.5 + friendliness
            case "surprise", "prank": m *= 0.5 + mischievousness
            case "cursor": m *= 0.5 + interaction
            case "explore", "scan": m *= 0.5 + curiosity
            default: break
            }
        }
        return m
    }
}
