import Foundation

public enum ContextState: String, Codable, Sendable, CaseIterable, Hashable {
    case activeWork = "ACTIVE_WORK"
    case reading = "READING"
    case idle = "IDLE"
    case fullScreen = "FULL_SCREEN"
    case presentation = "PRESENTATION"
    case videoCall = "VIDEO_CALL"
    case gaming = "GAMING"
    case locked = "LOCKED"
}

/// Raw signals from the context monitors. Unknown signals default to "not happening".
public struct ContextSignals: Sendable, Hashable {
    public var idleSeconds: Double = 0
    public var isLocked = false
    public var frontmostIsFullScreen = false
    public var inMeeting = false
    public var isGaming = false
    public var isPresenting = false
    public var frontmostIsReadingApp = false
    /// Seconds since the last key press (any input still counts towards `idleSeconds`).
    public var secondsSinceKeystroke: Double = 0
    /// Why the meeting flag is set, for the debug overlay and Settings (e.g. "microphone in use").
    public var meetingReason: String?
    public var frontmostBundleID: String?

    public init(idleSeconds: Double = 0, isLocked: Bool = false) {
        self.idleSeconds = idleSeconds
        self.isLocked = isLocked
    }

    /// Seconds without typing, while still using the mouse or scrolling, before a reading app counts as READING.
    public static let readingAfterSeconds = 30.0
}

public enum ContextClassifier {
    /// Highest-priority signal wins: the states that must never be interrupted come first.
    public static func classify(_ s: ContextSignals, idleThreshold: Double) -> ContextState {
        if s.isLocked { return .locked }
        if s.isPresenting { return .presentation }
        if s.inMeeting { return .videoCall }
        if s.isGaming { return .gaming }
        if s.frontmostIsFullScreen { return .fullScreen }
        if s.idleSeconds >= idleThreshold { return .idle }
        if s.frontmostIsReadingApp && s.secondsSinceKeystroke >= ContextSignals.readingAfterSeconds { return .reading }
        return .activeWork
    }
}

/// What the pets may do in a context (spec §10).
public struct ContextPolicy: Codable, Sendable, Hashable {
    public var paused: Bool
    /// > 1 means more frequent appearances.
    public var frequencyMultiplier: Double
    public var allowedTiers: Set<SceneTier>
    public var audioAllowed: Bool
    /// Preferred regions (used by the M5 planner). Empty = any.
    public var preferredRegions: [SceneRegion]

    public init(paused: Bool, frequencyMultiplier: Double = 1, allowedTiers: Set<SceneTier> = Set(SceneTier.allCases),
                audioAllowed: Bool = false, preferredRegions: [SceneRegion] = []) {
        self.paused = paused
        self.frequencyMultiplier = frequencyMultiplier
        self.allowedTiers = allowedTiers
        self.audioAllowed = audioAllowed
        self.preferredRegions = preferredRegions
    }

    public static let pausedPolicy = ContextPolicy(paused: true, frequencyMultiplier: 0, allowedTiers: [])
}

public enum PolicyTable {
    public static func defaultPolicy(for state: ContextState) -> ContextPolicy {
        switch state {
        case .activeWork:
            // Low frequency, short cameos, no audio.
            ContextPolicy(paused: false, frequencyMultiplier: 0.6, allowedTiers: [.quick, .funny, .rare],
                          audioAllowed: false, preferredRegions: [.bottomEdge, .sideEdge, .topEdge])
        case .reading:
            // Edge animations, short cameos.
            ContextPolicy(paused: false, frequencyMultiplier: 0.8, allowedTiers: [.quick],
                          audioAllowed: false, preferredRegions: [.sideEdge, .bottomEdge])
        case .idle:
            // More frequent, longer scenes.
            ContextPolicy(paused: false, frequencyMultiplier: 1.5, allowedTiers: Set(SceneTier.allCases), audioAllowed: true)
        case .fullScreen, .presentation, .videoCall, .gaming, .locked:
            .pausedPolicy
        }
    }

    /// Default policy with the user's toggles and per-state frequency overrides applied.
    public static func policy(for state: ContextState, settings: AppSettings) -> ContextPolicy {
        var p = defaultPolicy(for: state)
        if let f = settings.contextFrequency[state.rawValue], !p.paused { p.frequencyMultiplier = max(f, 0.05) }
        switch state {
        case .fullScreen where !settings.pauseDuringFullScreen || settings.debugAllowOverFullScreen,
             .gaming where !settings.pauseWhileGaming:
            p = ContextPolicy(paused: false, frequencyMultiplier: 0.5, allowedTiers: [.quick])
        case .videoCall where !settings.pauseDuringMeetings:
            p = ContextPolicy(paused: false, frequencyMultiplier: 0.3, allowedTiers: [.quick])
        default:
            break
        }
        if !settings.soundsEnabled { p.audioAllowed = false }
        if settings.soundsOnlyWhenIdle && state != .idle { p.audioAllowed = false }
        if settings.muteSoundsInMeetings && state == .videoCall { p.audioAllowed = false }
        return p
    }
}
