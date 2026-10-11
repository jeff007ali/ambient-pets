import CoreGraphics
import Foundation

/// `clips.json`: animation id → frames, fps, loop, plus an optional fallback chain.
public struct ClipsFile: Codable, Sendable {
    public var formatVersion: Int?
    public var clips: [String: ClipDefinition]
}

public struct ClipDefinition: Codable, Sendable, Hashable {
    public var frames: [String]?
    public var fps: Double
    public var loop: Bool
    /// Clip to use when this one has no frames (e.g. `hud_scan` → `idle`).
    public var fallback: String?
    /// Mirror the sprite when facing away from the atlas' native facing.
    public var mirrorForLeft: Bool
    /// Named attachment points (e.g. `thruster`, `hand`, `head`) relative to the pivot: px as drawn in the atlas, y up.
    public var points: [String: [Double]]?
    /// Direction thrusters fire for this pose: `down` (standing/hovering) or `back` (flying).
    public var thrustDirection: String?
    /// Body lean in degrees while this clip plays; positive leans forward (e.g. an upright pose used for flight).
    public var lean: Double?

    public init(frames: [String]?, fps: Double = 8, loop: Bool = true, fallback: String? = nil) {
        self.frames = frames
        self.fps = fps
        self.loop = loop
        self.fallback = fallback
        self.mirrorForLeft = true
    }

    enum CodingKeys: String, CodingKey { case frames, fps, loop, fallback, mirrorForLeft, points, thrustDirection, lean }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        frames = try c.decodeIfPresent([String].self, forKey: .frames)
        fps = try c.decode(.fps, default: 8)
        loop = try c.decode(.loop, default: true)
        fallback = try c.decodeIfPresent(String.self, forKey: .fallback)
        mirrorForLeft = try c.decode(.mirrorForLeft, default: true)
        points = try c.decodeIfPresent([String: [Double]].self, forKey: .points)
        thrustDirection = try c.decodeIfPresent(String.self, forKey: .thrustDirection)
        lean = try c.decodeIfPresent(Double.self, forKey: .lean)
    }

    public var hasFrames: Bool { !(frames ?? []).isEmpty }
}

/// A clip after following its fallback chain.
public struct ResolvedClip: Sendable, Hashable {
    /// The id the scene asked for.
    public var requestedID: String
    /// The id that actually supplied frames.
    public var sourceID: String
    public var definition: ClipDefinition
    public var frames: [String]

    public func frameName(at elapsed: Double) -> String {
        let n = frames.count
        guard n > 1 else { return frames[0] }
        let i = Int(max(elapsed, 0) * max(definition.fps, 0.01))
        return definition.loop ? frames[i % n] : frames[min(i, n - 1)]
    }

    /// A named attachment point (native px from the pivot, y up).
    public func point(_ name: String) -> CGPoint? {
        guard let p = definition.points?[name], p.count == 2 else { return nil }
        return CGPoint(x: p[0], y: p[1])
    }
}

public enum ClipResolutionError: Error, Equatable, CustomStringConvertible {
    case missing(String)
    case cycle([String])

    public var description: String {
        switch self {
        case .missing(let id): "clip '\(id)' is not defined"
        case .cycle(let chain): "fallback cycle: \(chain.joined(separator: " → "))"
        }
    }
}

public struct ClipLibrary: Sendable {
    public let clips: [String: ClipDefinition]

    public init(_ clips: [String: ClipDefinition]) { self.clips = clips }

    public func resolve(_ id: String) -> Result<ResolvedClip, ClipResolutionError> {
        var chain: [String] = []
        var current = id
        while true {
            if chain.contains(current) { return .failure(.cycle(chain + [current])) }
            chain.append(current)
            guard let def = clips[current] else { return .failure(.missing(current)) }
            if let frames = def.frames, !frames.isEmpty {
                return .success(ResolvedClip(requestedID: id, sourceID: current, definition: def, frames: frames))
            }
            guard let next = def.fallback else { return .failure(.missing(current)) }
            current = next
        }
    }

    /// Never fails if the library has any playable clip: `id` → `idle` → first playable clip.
    public func resolveOrDefault(_ id: String) -> ResolvedClip? {
        if case .success(let c) = resolve(id) { return c }
        if case .success(var c) = resolve("idle") { c.requestedID = id; return c }
        for key in clips.keys.sorted() {
            if case .success(var c) = resolve(key) { c.requestedID = id; return c }
        }
        return nil
    }
}
